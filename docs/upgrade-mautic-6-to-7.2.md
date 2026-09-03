# Upgrading Mautic 6.x to 7.2

This procedure was validated for a Docker setup with:

- `php:8.3-apache` or `php:8.3-fpm`
- MariaDB 11.8
- a persistent `/var/www/html` volume
- an existing Mautic 6.x install already running from a mounted volume

## Summary

When the application tree lives in a persistent volume, upgrading the image tag alone is not enough.
You must also refresh the files in `/var/www/html` so the mounted code matches the new Mautic release.

For Mautic 7.2, the application tree can be rebuilt from the `ghcr.io/librecodecoop/mautic:7.2-apache` image by running Composer inside that image.

## What to preserve

Keep the runtime data that belongs to the installation, not to the codebase:

- `config/local.php`
- `docroot/media`
- `var/logs`

If you already keep additional local overrides, back those up before syncing the tree.

Make sure `config/local.php` contains `site_url`. The `mautic_worker` and `mautic_cron` entrypoints wait for that key before starting.

Also make sure the cron environment exports the database variables used by the jobs. In particular, the running container must expose both `MAUTIC_DB_NAME` and the `MAUTIC_DB_DATABASE` alias so commands like `mautic:segments:update` do not fall back to a broken default connection.

## Recommended flow

1. Stop the Mautic services.
2. Back up the persistent volume contents.
3. Generate a clean Mautic 7.2 tree outside the live volume.
4. Sync the new tree into the mounted `/var/www/html` volume.
5. Restart the stack.
6. Run the Doctrine migrations and verify the version.

## Tree generation

Use the Mautic image itself as the Composer environment. That avoids host dependency mismatches and gives you the exact runtime PHP extensions used by the container.

Example:

```bash
docker run --rm -u 0:0 --entrypoint sh \
  -v /tmp/mautic-7.2-tree:/work \
  -w /work \
  ghcr.io/librecodecoop/mautic:7.2-apache \
  -lc 'composer create-project mautic/recommended-project:7.2.0 mautic --no-interaction --no-install && cd /work/mautic && composer install --no-interaction --no-dev --prefer-dist --optimize-autoloader'
```

The Composer scaffold may try to run `npm ci` during a post-update step. That is not required for the PHP application tree itself, because Mautic 7.2 ships with the frontend assets already built.

## Sync

After the tree is generated, sync it into the mounted volume:

```bash
rsync -a --delete /tmp/mautic-7.2-tree/mautic/ volumes/mautic/
```

If you need to preserve local config or media, copy those back after the sync.

## Migration edge case

During the 6.0.7 -> 7.2 upgrade on MariaDB 11.8 we hit a foreign key migration failure caused by a signed `id` column being referenced by an unsigned `translation_parent_id` column.

The affected migrations were:

- `Mautic\Migrations\Version20250828070131`
- `Mautic\Migrations\Version20250923135527`

The workaround was to apply the schema change manually with a signed `int(11)` column, create the index, add the foreign key, and mark the migrations as executed before re-running the remaining migrations.

## Verification

Run these checks after the restart:

```bash
docker compose exec -T mautic_web php bin/console --version
docker compose ps
docker compose logs --tail=80 mautic_web
```

You want to see:

- `Mautic 7.2.0`
- the `mautic_web` container healthy
- no remaining migration failures in the logs
- the cron jobs can resolve the database connection without `SQLSTATE[HY000] [2002] No such file or directory`
