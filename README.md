<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/herder-lockup-dark.svg">
    <img src="assets/herder-lockup-light.svg" height="64" alt="ispx herder">
  </picture>
  <br><br>
  <a href="https://discord.gg/grSq5zZRH"><img src="https://img.shields.io/badge/Discord-join%20the%20ispx%20server-5865F2?logo=discord&logoColor=white" alt="Discord"></a>
</div>

# Herder Community Edition

A complete ACS on one machine. Herder manages TR-069 and TR-369 (USP)
fleets: zero-touch provisioning, firmware campaigns, streaming
telemetry, per-subscriber WiFi insight, and a GitOps workflow over
device configuration. The Community Edition is the full product, free
to run, limited to 10 CPEs.

If you have Docker and a lab CPE, you are about ten minutes from a
managed device.

## Quickstart

```sh
git clone https://github.com/ispx-limited/herder-community
cd herder-community
./up.sh
```

The first run writes `.env` with generated secrets and stops. Set
`ACS_HOST` to the address your CPEs will dial, the host's LAN IP or
DNS name, then:

```sh
./up.sh
docker compose exec herderapi /app/community_entry.bin provision --admin
```

The administrator password is printed once. Sign in at
https://localhost; the certificate comes from Caddy's internal CA, so
the browser warns the first time.

## Connect a CPE

- TR-069: point the CPE at `http://<ACS_HOST>:7547/` with the factory
  credentials written to `config/cwmp-factory.yaml`.
- TR-369: MQTT on `<ACS_HOST>:1883`.

The [Community Edition guide](https://docs.herder.ispx.co/guides/community-edition/)
walks from first sign-in to a connected, provisioned device. The rest
of the documentation lives at [docs.herder.ispx.co](https://docs.herder.ispx.co/).

## What you get

One host, eleven containers:

| Piece | What it does |
| --- | --- |
| herder | The ACS in one process: the CWMP and USP adapters, provisioning, telemetry, firmware delivery, experience scores, jobs, webhooks |
| configservice | Syncs the mapping, telemetry and provisioning YAML the other roles read, from the bundled defaults or a Git repository |
| herder-api, frontend | The northbound API and the console, behind Caddy |
| postgres, pgbouncer | Device inventory and state |
| clickhouse | Telemetry history |
| nats | The message bus and the USP MQTT listener |
| redis | Sessions and caching |

Requirements: Docker Engine with the compose plugin and about 4 GB of
RAM.

## The 10 CPE limit

The Community Edition admits 10 CPEs. Known devices keep working; the
next device beyond the limit is refused at registration, over either
protocol, and the refusal is logged. The limit is compiled into the
binaries, not read from configuration. A larger fleet is a licensed
deployment.

## Licensed edition

The same files run the full product. ispx issues two things for a
licensed deployment: a registry token, because the licensed images are
private, and a licence token stating the device cap and the term. In
`.env` set `HERDER_EDITION=licensed` and `HERDER_REGISTRY_TOKEN` to the
registry token, save the licence token as `license.txt` next to
`.env`, and run `./up.sh`. The first administrator is then created with

```sh
docker compose exec herderapi python -m app.provision --admin
```

The licence page under Platform shows the term, the fleet against the
cap and the instance id a renewal is issued against. What the licence
covers and what happens when it lapses is in the
[licensing guide](https://docs.herder.ispx.co/guides/licensing/).

A Community Edition install becomes a licensed one the same way, on
the same data: the fleet, its history and its configuration carry
over, and only the images change.

## Upgrading

Set `HERDER_VERSION` in `.env` to the new release and run `./up.sh`
again; migrations run before the new images start. Releases are listed
in the [changelog](https://docs.herder.ispx.co/changelog/).

## Good to know

- The containers run as uid 1000 and own the generated `keys/`,
  `secrets/` and `nkeys/`. `up.sh` hands them over when run as root; from
  another account, `sudo chown -R 1000:1000 keys secrets nkeys` does the
  same.
- The published ports (80, 443, 7547, 7549, 1883) bind on all
  interfaces. A lab host belongs behind a firewall you trust.
- `keys/default` seals every credential Herder stores. Back it up
  with the database; losing it orphans them.
- Containers run as uid 1000 and read the generated files under
  `keys/`, `secrets/` and `nkeys/`. A different host uid needs a
  chown after generation.
- This is the evaluation shape: one host, no HA, no split stores, no
  inter-host TLS, no backups.
- The stack sends ispx one usage report a day: aggregate counts by
  vendor, model and firmware, load and feature use, never a serial
  number or an address. The licence page shows each report verbatim
  and has the switch; `USAGE_REPORTING=off` in `.env` does the same.
  Details in the [Usage Reporting guide](https://docs.herder.ispx.co/guides/usage-reporting/).

## Getting help

Issues and questions are welcome here and answered on a best effort
basis; there is no SLA. The documentation is the fastest path for
most questions, and the [ispx Discord](https://discord.gg/grSq5zZRH) is where
the conversation happens.

## License

The files in this repository are Apache-2.0. The container images
hold Herder itself, which is proprietary; EULA.md carries its terms.
