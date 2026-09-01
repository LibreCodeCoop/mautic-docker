#!/bin/bash

set -e

prepare_install_dirs() {
	mkdir -p /var/www/html/var/cache /var/www/html/var/logs
	chown -R www-data:www-data /var/www/html/config /var/www/html/var /var/www/html/docroot/media
}

prepare_install_dirs

mautic_site_url="${MAUTIC_SITE_URL:-http://localhost}"
mautic_admin_firstname="${MAUTIC_ADMIN_FIRSTNAME:-Admin}"
mautic_admin_lastname="${MAUTIC_ADMIN_LASTNAME:-Mautic}"
mautic_admin_username="${MAUTIC_ADMIN_USERNAME:-admin}"
mautic_admin_email="${MAUTIC_ADMIN_EMAIL:-admin@example.com}"
mautic_admin_password="${MAUTIC_ADMIN_PASSWORD:-ChangeMe123!}"
mautic_db_table_prefix="${MAUTIC_DB_TABLE_PREFIX:-}"
mautic_db_backup_tables="${MAUTIC_DB_BACKUP_TABLES:-true}"
mautic_db_backup_prefix="${MAUTIC_DB_BACKUP_PREFIX:-bak_}"
mautic_force_install="${MAUTIC_FORCE_INSTALL:-false}"

install_mautic() {
	local mautic_db_name="${MAUTIC_DB_DATABASE:-${MAUTIC_DB_NAME:-mautic}}"
	local cmd

	printf -v cmd 'php /var/www/html/bin/console mautic:install %q --force --db_driver=pdo_mysql --db_host=%q --db_port=%q --db_name=%q --db_user=%q --db_password=%q --db_table_prefix=%q --db_backup_tables=%q --db_backup_prefix=%q --admin_firstname=%q --admin_lastname=%q --admin_username=%q --admin_email=%q --admin_password=%q' \
		"$mautic_site_url" \
		"$MAUTIC_DB_HOST" \
		"$MAUTIC_DB_PORT" \
		"$mautic_db_name" \
		"$MAUTIC_DB_USER" \
		"$MAUTIC_DB_PASSWORD" \
		"$mautic_db_table_prefix" \
		"$mautic_db_backup_tables" \
		"$mautic_db_backup_prefix" \
		"$mautic_admin_firstname" \
		"$mautic_admin_lastname" \
		"$mautic_admin_username" \
		"$mautic_admin_email" \
		"$mautic_admin_password"

	su -s /bin/bash www-data -c "$cmd"
}

install_mautic_plugins() {
	su -s /bin/bash www-data -c 'php /var/www/html/bin/console mautic:plugins:install'
}

mautic_is_installed() {
	# shellcheck disable=SC2016
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

if [ "$mautic_force_install" = "true" ]; then
	rm -f /var/www/html/config/local.php
fi

prepare_install_dirs

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

	install_mautic_plugins
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
	install_mautic_plugins
	su -s /bin/bash www-data -c 'php /var/www/html/bin/console doctrine:fixtures:load -n'
fi

# run migrations
if [ "$DOCKER_MAUTIC_RUN_MIGRATIONS" = "true" ]; then
	su -s /bin/bash www-data -c 'php /var/www/html/bin/console doctrine:migration:migrate -n'
fi

# execute the provided entrypoint
"$@"
