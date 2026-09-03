#!/bin/bash

# Set uid of host machine
usermod --non-unique --uid "${HOST_UID}" www-data
groupmod --non-unique --gid "${HOST_GID}" www-data

if [ "$DOCKER_MAUTIC_ROLE" = "mautic_worker" ]; then
	/entrypoint_mautic_worker.sh
elif [ "$DOCKER_MAUTIC_ROLE" = "mautic_cron" ]; then
	/entrypoint_mautic_cron.sh
elif [ "$DOCKER_MAUTIC_ROLE" = "mautic_web" ]; then
	if [ ! -f /var/www/html/composer.json ]; then
		cd /var/www || { echo "Directory not found /var/www"; exit 1; }
		COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_PROCESS_TIMEOUT=10000 composer create-project mautic/recommended-project:"${MAUTIC_VERSION:-7.x-dev}" html --no-interaction
		chown -R www-data: html
		cd html || { echo "Directory not found /var/www/html"; exit 1; }
		rm -rf var/cache/js
		mkdir -p html/config html/var/logs html/docroot/media
	fi
	/entrypoint_mautic_web.sh "$@"
else
	echo "no entrypoint specified, exiting"
	exit 1
fi
