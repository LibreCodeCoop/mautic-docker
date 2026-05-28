#!/bin/bash

set -e

chown -R www-data:www-data /var/www/html/config /var/www/html/var/logs /var/www/html/docroot/media

mautic_site_url="${MAUTIC_SITE_URL:-http://localhost}"
mautic_admin_firstname="${MAUTIC_ADMIN_FIRSTNAME:-Admin}"
mautic_admin_lastname="${MAUTIC_ADMIN_LASTNAME:-Mautic}"
mautic_admin_username="${MAUTIC_ADMIN_USERNAME:-admin}"
mautic_admin_email="${MAUTIC_ADMIN_EMAIL:-admin@example.com}"
mautic_admin_password="${MAUTIC_ADMIN_PASSWORD:-ChangeMe123!}"
mautic_db_table_prefix="${MAUTIC_DB_TABLE_PREFIX:-}"
mautic_db_backup_tables="${MAUTIC_DB_BACKUP_TABLES:-true}"
mautic_db_backup_prefix="${MAUTIC_DB_BACKUP_PREFIX:-bak_}"

install_mautic() {
	su -s /bin/bash www-data -c 'php /var/www/html/bin/console mautic:install "$MAUTIC_SITE_URL" --force \
		--db_driver=pdo_mysql \
		--db_host="$MAUTIC_DB_HOST" \
		--db_port="$MAUTIC_DB_PORT" \
		--db_name="$MAUTIC_DB_DATABASE" \
		--db_user="$MAUTIC_DB_USER" \
		--db_password="$MAUTIC_DB_PASSWORD" \
		--db_table_prefix="$MAUTIC_DB_TABLE_PREFIX" \
		--db_backup_tables="$MAUTIC_DB_BACKUP_TABLES" \
		--db_backup_prefix="$MAUTIC_DB_BACKUP_PREFIX" \
		--admin_firstname="$MAUTIC_ADMIN_FIRSTNAME" \
		--admin_lastname="$MAUTIC_ADMIN_LASTNAME" \
		--admin_username="$MAUTIC_ADMIN_USERNAME" \
		--admin_email="$MAUTIC_ADMIN_EMAIL" \
		--admin_password="$MAUTIC_ADMIN_PASSWORD"'
}

mautic_is_installed() {
	php -r 'if (!file_exists("/var/www/html/config/local.php")) { exit(1); } include "/var/www/html/config/local.php"; exit(isset($parameters["db_driver"], $parameters["site_url"]) ? 0 : 1);'
}

# wait until the db is fully up before proceeding
while [[ $(mysqladmin --host="$MAUTIC_DB_HOST" --port="$MAUTIC_DB_PORT" --user="$MAUTIC_DB_USER" --password="$MAUTIC_DB_PASSWORD" ping) != "mysqld is alive" ]]; do
	sleep 1
done

# generate a local config file if it doesn't exist.
# This is needed to ensure the db credentials can be prefilled in the UI, as env vars aren't taken into account.
if [ ! -f /var/www/html/config/local.php ]; then
	su -s /bin/bash www-data -c 'touch /var/www/html/config/local.php'

	cat <<'EOF' > /var/www/html/config/local.php
<?php
$parameters = array(
	'db_driver' => 'pdo_mysql',
	'db_host' => getenv('MAUTIC_DB_HOST'),
	'db_port' => getenv('MAUTIC_DB_PORT'),
	'db_name' => getenv('MAUTIC_DB_DATABASE'),
	'db_user' => getenv('MAUTIC_DB_USER'),
	'db_password' => getenv('MAUTIC_DB_PASSWORD'),
	'db_table_prefix' => null,
	'db_backup_tables' => 1,
	'db_backup_prefix' => 'bak_',
);
EOF
fi

if [ "$MAUTIC_AUTO_INSTALL" = "true" ] && [ -f /var/www/html/config/local.php ]; then
	if ! mautic_is_installed; then
		rm -f /var/www/html/config/local.php
	fi
fi

if [ "$MAUTIC_AUTO_INSTALL" = "true" ] && [ ! -f /var/www/html/config/local.php ]; then
	MAUTIC_SITE_URL="$mautic_site_url" \
	MAUTIC_ADMIN_FIRSTNAME="$mautic_admin_firstname" \
	MAUTIC_ADMIN_LASTNAME="$mautic_admin_lastname" \
	MAUTIC_ADMIN_USERNAME="$mautic_admin_username" \
	MAUTIC_ADMIN_EMAIL="$mautic_admin_email" \
	MAUTIC_ADMIN_PASSWORD="$mautic_admin_password" \
	MAUTIC_DB_TABLE_PREFIX="$mautic_db_table_prefix" \
	MAUTIC_DB_BACKUP_TABLES="$mautic_db_backup_tables" \
	MAUTIC_DB_BACKUP_PREFIX="$mautic_db_backup_prefix" \
	install_mautic
fi

# prepare mautic with test data
if [ "$DOCKER_MAUTIC_LOAD_TEST_DATA" = "true" ]; then
	su -s /bin/bash www-data -c 'php /var/www/html/bin/console doctrine:migrations:sync-metadata-storage'
	# mautic installation with dummy password and email, as the next step (doctrine:fixtures:load) will overwrite those
	if ! mautic_is_installed; then
		MAUTIC_SITE_URL="$mautic_site_url" \
		MAUTIC_ADMIN_FIRSTNAME="$mautic_admin_firstname" \
		MAUTIC_ADMIN_LASTNAME="$mautic_admin_lastname" \
		MAUTIC_ADMIN_USERNAME="$mautic_admin_username" \
		MAUTIC_ADMIN_EMAIL="$mautic_admin_email" \
		MAUTIC_ADMIN_PASSWORD="$mautic_admin_password" \
		MAUTIC_DB_TABLE_PREFIX="$mautic_db_table_prefix" \
		MAUTIC_DB_BACKUP_TABLES="$mautic_db_backup_tables" \
		MAUTIC_DB_BACKUP_PREFIX="$mautic_db_backup_prefix" \
		install_mautic
	fi
	su -s /bin/bash www-data -c 'php /var/www/html/bin/console doctrine:fixtures:load -n'
fi

# run migrations
if [ "$DOCKER_MAUTIC_RUN_MIGRATIONS" = "true" ]; then
	su -s /bin/bash www-data -c 'php /var/www/html/bin/console doctrine:migration:migrate -n'
fi

# execute the provided entrypoint
"$@"
