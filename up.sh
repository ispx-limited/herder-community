#!/usr/bin/env bash
# First run: generates the secrets and key material the stack needs,
# then migrates and starts it. Later runs: migrates and starts. The
# generated files live in .env, keys/, secrets/, config/, nkeys/ and
# pgbouncer/userlist.txt, all gitignored. Losing keys/default orphans
# every credential the stack has sealed; back it up with the database.
set -euo pipefail
cd "$(dirname "$0")"

rand() { openssl rand -hex 24; }

if [ ! -f .env ]; then
    cp .env.example .env
    for var in POSTGRES_PASSWORD CLICKHOUSE_PASSWORD NATS_SYS_PASSWORD \
        NATS_HERDER_PASSWORD NATS_DEVICES_PASSWORD NATS_AUTHSERVICE_PASSWORD \
        USP_MQTT_DEVICE_SECRET FIRMWARE_SIGNING_KEY CWMP_FACTORY_PASSWORD; do
        sed -i "s/^${var}=$/${var}=$(rand)/" .env
    done
    chmod 600 .env
    echo "wrote .env with generated secrets; review ACS_HOST and HERDER_HOSTNAME"
fi

set -a
. ./.env
set +a

mkdir -p keys secrets config nkeys

# The containers read these as uid 1000.
if [ ! -f keys/default ]; then
    (umask 177 && openssl rand -out keys/default 32)
fi
if [ ! -f keys/cwmp-nonce ]; then
    (umask 177 && openssl rand -out keys/cwmp-nonce 32)
fi

(umask 177 && printf 'postgres://herder:%s@pgbouncer:6432/herder?sslmode=disable' \
    "${POSTGRES_PASSWORD}" > secrets/db_dsn)

(umask 133 && printf '"herder" "%s"\n' "${POSTGRES_PASSWORD}" > pgbouncer/userlist.txt)

# The factory credentials CPEs must present on their first CWMP
# session. "*" matches any OUI; {OUI} and {serial} expand per device.
if [ ! -f config/cwmp-factory.yaml ]; then
    (umask 177 && printf 'factory_defaults:\n  - oui: "*"\n    username: herder\n    password: %s\n' \
        "${CWMP_FACTORY_PASSWORD}" > config/cwmp-factory.yaml)
fi

# The NATS auth-callout key pair for USP. nkeygen ships in the herder
# image; the seed is read by the auth responder, the conf by NATS.
if [ ! -f nkeys/authcallout.conf ]; then
    docker run --rm -v "$(pwd)/nkeys:/nkeys" --entrypoint nkeygen \
        "ghcr.io/ispx-limited/herder-community:${HERDER_VERSION}" \
        --seed=/nkeys/issuer.seed --conf=/nkeys/authcallout.conf \
        --account=AuthCallout --user=authservice,sys,herder,devices \
        --password=unused --enabled=true
fi

docker compose --profile migrate run --rm migrate
docker compose up -d

echo
echo "console:  https://${HERDER_HOSTNAME}$( [ "${HTTPS_PORT}" = 443 ] || printf ':%s' "${HTTPS_PORT}" )"
echo "TR-069:   http://${ACS_HOST}:${CWMP_PORT}/ (credentials: config/cwmp-factory.yaml)"
echo "TR-369:   mqtt://${ACS_HOST}:${MQTT_PORT}"
echo
echo "first run: create the administrator (the password is printed once):"
echo "  docker compose exec herderapi /app/community_entry.bin provision --admin"
