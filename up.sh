#!/usr/bin/env bash
# First run: generates the secrets and key material the stack needs,
# then migrates and starts it. Later runs: migrates and starts. The
# generated files live in .env, keys/, secrets/, config/, nkeys/ and
# pgbouncer/userlist.txt, all gitignored. Losing keys/default orphans
# every credential the stack has sealed; back it up with the database.
set -euo pipefail
cd "$(dirname "$0")"

# The letter prefix is load-bearing: NATS parses substituted env
# values as config tokens, and a value that starts with a digit and
# continues with letters is a parse error that keeps NATS restarting.
rand() { printf 'p%s' "$(openssl rand -hex 24)"; }

if [ ! -f .env ]; then
    cp .env.example .env
    for var in POSTGRES_PASSWORD CLICKHOUSE_PASSWORD NATS_SYS_PASSWORD \
        NATS_HERDER_PASSWORD NATS_DEVICES_PASSWORD NATS_AUTHSERVICE_PASSWORD \
        USP_MQTT_DEVICE_SECRET FIRMWARE_SIGNING_KEY CWMP_FACTORY_PASSWORD \
        XMPP_ACS_PASSWORD; do
        sed -i "s/^${var}=$/${var}=$(rand)/" .env
    done
    chmod 600 .env
    echo "wrote .env with generated secrets."
    echo "set ACS_HOST to the address CPEs will dial, review HERDER_HOSTNAME"
    echo "and the ports, then run ./up.sh again."
    echo "usage reporting to ispx is on (aggregate counts, never a serial or"
    echo "an address); set USAGE_REPORTING=off in .env to stop it."
    exit 0
fi

# A release can add a secret the deployment's .env predates; fill it in
# so the compose file's ${VAR:?} does not stop the upgrade.
for var in XMPP_ACS_PASSWORD; do
    grep -q "^${var}=" .env || printf '%s=%s\n' "$var" "$(rand)" >> .env
done

set -a
. ./.env
set +a

# .env is written once and never touched by git pull, so the release it
# pins goes stale while .env.example moves on. Say so rather than run
# an old release in silence; the pin is the operator's to change.
# Only an older pin is worth a word: a newer one is the operator ahead
# of this checkout, and the pin in .env always wins either way.
latest=$(sed -n 's/^HERDER_VERSION=//p' .env.example)
if [ -n "$latest" ] && [ -n "${HERDER_VERSION:-}" ] && [ "$latest" != "$HERDER_VERSION" ] \
    && [ "$(printf '%s\n%s\n' "$HERDER_VERSION" "$latest" | sort -V | head -n1)" = "$HERDER_VERSION" ]; then
    echo "note: .env pins HERDER_VERSION=${HERDER_VERSION}; the current release is ${latest}."
    echo "      To upgrade, set HERDER_VERSION=${latest} in .env and run ./up.sh again."
fi

# The edition picks the images. The suffix is written back into .env so
# a plain docker compose command sees the same images up.sh does.
case "${HERDER_EDITION:-community}" in
    community) HERDER_IMAGE_SUFFIX=-community ;;
    licensed) HERDER_IMAGE_SUFFIX= ;;
    *) echo "HERDER_EDITION must be community or licensed" >&2; exit 1 ;;
esac
export HERDER_IMAGE_SUFFIX
if grep -q '^HERDER_IMAGE_SUFFIX=' .env; then
    sed -i "s/^HERDER_IMAGE_SUFFIX=.*/HERDER_IMAGE_SUFFIX=${HERDER_IMAGE_SUFFIX}/" .env
else
    printf 'HERDER_IMAGE_SUFFIX=%s\n' "$HERDER_IMAGE_SUFFIX" >> .env
fi

# The licence token. The Community Edition takes none and the file
# stays empty; the licensed edition installs it on start, and until one
# is in place the console opens on the licence page alone.
touch license.txt
if [ "$HERDER_EDITION" = licensed ]; then
    # The licensed images are private. The token ispx issued is the
    # registry credential; it lives in .env (mode 600) and nowhere else.
    if [ -n "${HERDER_REGISTRY_TOKEN:-}" ]; then
        printf '%s' "$HERDER_REGISTRY_TOKEN" | docker login ghcr.io -u ispx-herder-pull --password-stdin >/dev/null
    fi
    if ! docker image inspect "ghcr.io/ispx-limited/herder:${HERDER_VERSION}" >/dev/null 2>&1 \
        && ! docker manifest inspect "ghcr.io/ispx-limited/herder:${HERDER_VERSION}" >/dev/null 2>&1; then
        echo "cannot read ghcr.io/ispx-limited/herder:${HERDER_VERSION}: set HERDER_REGISTRY_TOKEN in .env" >&2
        echo "to the registry credential ispx issued, or docker login ghcr.io -u ispx-herder-pull" >&2
        exit 1
    fi
    if [ ! -s license.txt ]; then
        echo "license.txt is empty; the console opens on the licence page until a licence is installed."
    fi
fi

mkdir -p keys secrets config nkeys

# The containers run as uid 1000 and write into these directories, so
# from a root shell they are handed to that user, the same step every
# compose file with a non-root image asks for.
if [ "$(id -u)" = 0 ]; then
    chown 1000:1000 keys secrets config nkeys
fi

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

# The NATS auth-callout key pair for USP agents, generated once. nkeygen
# ships in the herder image; the seed is read by the auth responder,
# the conf by NATS. The user list and the placeholder password are the
# NATS account wiring the conf file carries; nothing dials out.
if [ ! -f nkeys/authcallout.conf ]; then
    docker run --rm -v "$(pwd)/nkeys:/nkeys" --entrypoint nkeygen \
        "ghcr.io/ispx-limited/herder${HERDER_IMAGE_SUFFIX}:${HERDER_VERSION}" \
        --seed=/nkeys/issuer.seed --conf=/nkeys/authcallout.conf \
        --account=AuthCallout --user=authservice,sys,herder,devices \
        --password=unused --enabled=true
fi

if [ "$(id -u)" = 0 ]; then
    chown -R 1000:1000 keys secrets nkeys config
fi

docker compose --profile migrate run --rm migrate
docker compose up -d

if [ "$HERDER_EDITION" = licensed ]; then
    echo "first administrator: docker compose exec herderapi python -m app.provision --admin"
else
    echo "first administrator: docker compose exec herderapi /app/community_entry.bin provision --admin"
fi

echo
echo "console:  https://${HERDER_HOSTNAME}$( [ "${HTTPS_PORT}" = 443 ] || printf ':%s' "${HTTPS_PORT}" )"
echo "TR-069:   http://${ACS_HOST}:${CWMP_PORT}/ (credentials: config/cwmp-factory.yaml)"
echo "TR-369:   mqtt://${ACS_HOST}:${MQTT_PORT}"
echo
echo "first run: create the administrator (the password is printed once):"
echo "  docker compose exec herderapi /app/community_entry.bin provision --admin"
