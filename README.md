# Herder Community Edition

Herder is an ACS for TR-069 and TR-369 (USP) fleets: it configures
CPEs, streams their telemetry, and gives operators a GitOps workflow
over both. This repository runs the Community Edition with Docker
Compose: the full product, limited to 10 CPEs, for evaluation and lab
use.

The container images are proprietary; EULA.md carries the terms that
govern them. The files in this repository are Apache-2.0.

Documentation lives at https://docs.herder.ispx.co/.

## Requirements

- Docker Engine with the compose plugin.
- About 4 GB of RAM for the stack.
- A host the CPEs can reach. The stack publishes 80 and 443 (console
  and API), 7547 (TR-069), 7549 (firmware delivery) and 1883 (TR-369
  over MQTT) on all interfaces; put a lab host behind a firewall you
  trust.

## Quickstart

```
git clone https://github.com/ispx-limited/herder-community
cd herder-community
./up.sh
```

The first run writes `.env` with generated secrets. Edit it, set
`ACS_HOST` to the address CPEs will dial, and run `./up.sh` again.
Then create the administrator; the password is printed once:

```
docker compose exec herderapi /app/community_entry.bin provision --admin
```

The console is at https://localhost (or `HERDER_HOSTNAME` if set).
The certificate comes from Caddy's internal CA, so the browser warns
once.

## Pointing CPEs at it

- TR-069: `http://ACS_HOST:7547/`, with the factory credentials
  written to `config/cwmp-factory.yaml`.
- TR-369: MQTT on `ACS_HOST:1883`.

## Upgrading

Change `HERDER_VERSION` in `.env` and run `./up.sh` again; it runs
migrations before starting the stack.

## The device limit

The Community Edition admits at most 10 CPEs. The next device is
refused at registration and the refusal is logged. The limit is part
of the binaries, not of this configuration.

## What this is not

- Not open source. This repository is Apache-2.0; the product in the
  images is closed and obfuscated.
- Not a production shape. One host, no TLS between services, no host
  firewalling, no backups, no platform metrics store. Production
  Herder is delivered and operated differently; start at
  https://docs.herder.ispx.co/.
- Not supported under an SLA. Issues here are read and answered on a
  best effort basis.

## Notes

- The stack runs as uid 1000 inside the containers and reads the
  generated files under `keys/`, `secrets/` and `nkeys/`. If your
  user is not uid 1000, chown those files after `./up.sh` generates
  them.
- `keys/default` seals stored credentials. Losing it orphans them;
  back it up with the database.
