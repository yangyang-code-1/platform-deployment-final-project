#!/bin/sh
set -e

PORT="${PORT:-80}"
echo "Configuring Nginx to listen on port ${PORT}..."
sed -i "s/listen 80/listen ${PORT}/" /etc/nginx/conf.d/default.conf

echo "Waiting for database..."
TRIES=0
MAX_TRIES=60
until php bin/console dbal:run-sql "SELECT 1" --no-interaction > /dev/null 2>&1; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -ge "$MAX_TRIES" ]; then
        echo "ERROR: Database not available after ${MAX_TRIES} attempts. Check DATABASE_URL."
        exit 1
    fi
    echo "Database not ready, retrying in 2s... (${TRIES}/${MAX_TRIES})"
    sleep 2
done
echo "Database is ready."

echo "Running migrations..."
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

if [ "$APP_ENV" = "prod" ]; then
    echo "Warming production cache..."
    php bin/console cache:warmup --env=prod --no-debug
    if [ ! -f public/assets/manifest.json ]; then
        echo "Compiling assets..."
        php bin/console asset-map:compile --env=prod --no-debug
    fi
fi

echo "Fixing var directory permissions..."
chown -R www-data:www-data /app/var

echo "Starting PHP-FPM..."
php-fpm -D

echo "Starting Nginx on port ${PORT}..."
exec nginx -g "daemon off;"
