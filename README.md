# Paperless mail stack

Requires Docker Compose v2. Replace secrets in both environment files as appropriate; use `openssl rand -hex 32` for each secret. Change the production URL. Protect env files with chmod 600. Bind address defaults to loopback: use an HTTPS reverse proxy or change to a trusted LAN address for phone access. Do not expose PostgreSQL or Redis.

```sh
mkdir -p storage/{data,media,consume,export,ai,backups,postgres,redis} rclone
chmod 600 .env .env.production
docker compose --env-file .env --env-file .env.production up -d db redis tika gotenberg webserver
docker compose --env-file .env --env-file .env.production exec webserver createsuperuser
```

Configure OpenDrive and then a crypt remote named opendrive-crypt pointing to a dedicated folder on OpenDrive:

```sh
docker run --rm -it -v "$PWD/rclone:/config/rclone" rclone/rclone config
docker run --rm -v "$PWD/rclone:/config/rclone" rclone/rclone lsd opendrive-crypt:
```

Keep the rclone configuration and encryption passwords in a separate secure backup. Do not store the only copy on the encrypted remote itself.

Start all production services:

```sh
docker compose --env-file .env --env-file .env.production up -d --build
```

Paperless-AI: open its UI on port 3000 through a trusted connection. Configure the Paperless URL `http://webserver:8000`, API token and chosen AI provider in its setup UI. Its settings persist in storage/ai. Configure Paperless Mobile using the external HTTPS URL. For n8n use a Paperless workflow webhook if supported by your installed version, or poll its REST API for new documents. AI and n8n are not preconfigured.

Backup runs immediately and then every 86400 seconds by default. It uploads timestamped encrypted snapshots; SHA256SUMS is uploaded last as a completion marker. No remote retention/deletion is configured. Full snapshots can consume significant storage. Live database and filesystem snapshots are not atomic: for a consistent backup, pause ingestion and stop webserver and paperless-ai before running `docker compose --env-file .env --env-file .env.production exec backup /usr/local/bin/backup.sh once`, then restart them. Avoid concurrent backup runs. For portable application-level exports use `docker compose --env-file .env --env-file .env.production exec -T webserver document_exporter ../export` and copy the export separately to the encrypted remote.

Restore: download a completed timestamped snapshot using rclone, verify `sha256sum -c SHA256SUMS`, stop application services, restore media/data/ai archives into DATA_ROOT, and restore database.dump into an empty PostgreSQL database using pg_restore with matching credentials. Restore deployment files selectively. Rebuild search index if necessary. Test restore before relying on backups. The backup does not include pending consume files or Redis queue state. Keep version tags pinned after testing; latest is supplied for initial evaluation only.

This stack has not been run against a live Docker daemon or OpenDrive account. Check current image versions and application compatibility before production use.
# homedocs
