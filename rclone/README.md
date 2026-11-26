# OpenDrive remote

The backup service reads `rclone/rclone.conf`. Snapshots go to `opendrive-crypt:paperless-backup`, from `BACKUP_REMOTE` in `.env`.

`opendrive` is the OpenDrive account. `opendrive-crypt` encrypts the OpenDrive folder `paperless-backup`. File names and directory names are encrypted inside that folder. Each snapshot is a timestamped directory under `paperless-backup` on the crypt remote.

## Write the config

From the repository directory:

```sh
cp rclone/rclone.conf.example rclone/rclone.conf
chmod 600 rclone/rclone.conf
```

Set `username` under `[opendrive]` to the OpenDrive account email.

Password fields must be the output of `rclone obscure`, one value per secret. Use a different crypt passphrase and salt.

```sh
docker run --rm -it rclone/rclone obscure
```

Run it three times and paste the results into `rclone/rclone.conf`:

- OpenDrive account password → `[opendrive]` `password`
- Crypt passphrase → `[opendrive-crypt]` `password`
- Crypt salt → `[opendrive-crypt]` `password2`

`rclone config` can write the same two remotes and obscure the passwords for you. Name them `opendrive` and `opendrive-crypt`. Point the crypt remote at `opendrive:paperless-backup`, choose standard filename encryption, and encrypt directory names.

```sh
docker run --rm -it -v "$PWD/rclone:/config/rclone" -e RCLONE_CONFIG=/config/rclone/rclone.conf rclone/rclone config
```

## Check the account and create the folder

```sh
docker run --rm -it -v "$PWD/rclone:/config/rclone" -e RCLONE_CONFIG=/config/rclone/rclone.conf rclone/rclone lsd opendrive:
docker run --rm -it -v "$PWD/rclone:/config/rclone" -e RCLONE_CONFIG=/config/rclone/rclone.conf rclone/rclone mkdir opendrive:paperless-backup
docker run --rm -it -v "$PWD/rclone:/config/rclone" -e RCLONE_CONFIG=/config/rclone/rclone.conf rclone/rclone mkdir opendrive-crypt:paperless-backup
docker run --rm -v "$PWD/rclone:/config/rclone" -e RCLONE_CONFIG=/config/rclone/rclone.conf rclone/rclone lsd opendrive-crypt:paperless-backup
```

`lsd opendrive:` lists the account. The last command lists the encrypted backup folder and should succeed before you start the backup service.

Keep a separate copy of `rclone.conf` and both crypt secrets. The OpenDrive copy of the backups cannot be decrypted without them.
