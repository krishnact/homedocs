# Paperless mail stack

Requires Docker Compose v2 and OpenSSL. The bind address defaults to loopback. Use an HTTPS reverse proxy, or set a trusted LAN address for phone access. Do not expose PostgreSQL or Redis.

## Quickstart

From the repository directory on the Docker host:

```sh
chmod +x setup.sh stack.sh
./setup.sh
./stack.sh start
docker compose --env-file .env --env-file .env.production exec webserver createsuperuser
```

`./stack.sh stop` stops the stack. `./stack.sh help` lists the commands.

`setup.sh` creates `storage/data`, `storage/media`, `storage/consume`, `storage/export`, `storage/ai`, `storage/backups`, `storage/postgres`, `storage/redis`, and `rclone`. When `.env` or `.env.production` is missing, it copies the matching example, replaces each secret placeholder with its own `openssl rand -hex 32` value, and sets the file mode to 600. Existing env files are left in place and set to mode 600.

Every bind mount is a directory next to the compose file: service data under `storage/`, and the rclone config under `rclone/`. Copy or move this directory and the data goes with it.

`.env.production` overrides `.env` for `PAPERLESS_URL`, `POSTGRES_PASSWORD`, `PAPERLESS_SECRET_KEY`, and `COMPOSE_PROFILES`. Change `PAPERLESS_URL` in `.env.production`. The example value is `https://paperless.example.com`.

`stack.sh start` and `stack.sh stop` pass both env files. Compose loads `.env` on its own only when no `--env-file` flag is present, so the script names `.env` first and `.env.production` second:

```sh
docker compose --env-file .env --env-file .env.production up -d --build
docker compose --env-file .env --env-file .env.production stop
```

`start` builds the backup image and starts the services selected by `COMPOSE_PROFILES` in `.env.production`. The example enables `ai` and `backup`. Before that, it requires `POSTGRES_PASSWORD` and `PAPERLESS_SECRET_KEY`. A value already set in the shell wins, then `.env.production`, then `.env`. Empty values and the example placeholders are rejected. `stop` stops those containers and leaves them in place.

After the first start, create the Paperless user with the `createsuperuser` command above.

## OpenDrive

Copy `rclone/rclone.conf.example` to `rclone/rclone.conf` and fill in the OpenDrive account. The steps, including how to obscure the passwords, are in `rclone/README.md`.

The backup remote is `opendrive-crypt:paperless-backup`. `opendrive-crypt` encrypts the OpenDrive folder `paperless-backup`.

Keep a separate copy of `rclone/rclone.conf` and both crypt secrets. The copy stored on OpenDrive cannot be decrypted without them.

## Paperless-AI

Open the Paperless-AI UI on port 3000 through a trusted connection. In its setup UI, set the Paperless URL to `http://webserver:8000`, plus an API token and the chosen AI provider. Settings persist in `storage/ai`.

Configure Paperless Mobile with the external HTTPS URL.

For n8n, use a Paperless workflow webhook when the installed version supports it, or poll the REST API for new documents. AI and n8n are not preconfigured.

## Backup

Backup runs immediately, then every 86400 seconds by default. It uploads timestamped snapshots. `SHA256SUMS` is uploaded last as a completion marker. No remote retention or deletion is configured. Full snapshots can consume significant storage.

OpenDrive receives every snapshot through the encrypted `opendrive-crypt` remote. Set `DEGOO_EMAIL` and `DEGOO_PASSWORD` to also upload that snapshot with [cligoo](https://github.com/marcomc/cligoo). Leave both empty to skip Degoo. `DEGOO_REMOTE` defaults to `/Web/paperless-backup`. cligoo is an unofficial Degoo client. Degoo stores the files without the client-side encryption used for OpenDrive, and the deployment archive includes `.env` and `.env.production`.

Live database and filesystem snapshots are not atomic. For a consistent backup, pause ingestion and stop `webserver` and `paperless-ai`, run the command below, then restart them. Avoid concurrent backup runs.

```sh
docker compose --env-file .env --env-file .env.production exec backup /usr/local/bin/backup.sh once
```

For a portable application-level export:

```sh
docker compose --env-file .env --env-file .env.production exec -T webserver document_exporter ../export
```

Copy that export separately to the encrypted remote.

## Restore

1. Download a completed timestamped snapshot with rclone, or with `cligoo download /Web/paperless-backup/<stamp> -t ./restore -r` when the copy is on Degoo.
2. Verify it with `sha256sum -c SHA256SUMS`.
3. Stop the application services.
4. Restore the media, data, and ai archives into `storage/`.
5. Restore `database.dump` into an empty PostgreSQL database with `pg_restore` and matching credentials.
6. Restore deployment files selectively.
7. Rebuild the search index if necessary.

Test a restore before relying on backups. The backup does not include pending consume files or Redis queue state. Keep version tags pinned after testing. `latest` is supplied for initial evaluation only.

This stack has not been run against a live Docker daemon or OpenDrive account. Check current image versions and application compatibility before production use.
