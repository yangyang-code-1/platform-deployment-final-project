#!/bin/sh
set -e

PORT="${PORT:-80}"
echo "Configuring Nginx to listen on 0.0.0.0:${PORT}..."
sed -i "s/listen 0.0.0.0:80/listen 0.0.0.0:${PORT}/" /etc/nginx/conf.d/default.conf

if [ -n "$RAILWAY_ENVIRONMENT" ] && [ -z "$DATABASE_URL" ]; then
    echo "WARNING: RAILWAY_ENVIRONMENT is set but DATABASE_URL is empty."
    echo "Add DATABASE_URL in Railway app service variables (reference the MySQL service)."
fi

DB_OK=0
echo "Waiting for database..."
TRIES=0
MAX_TRIES=30
while [ "$TRIES" -lt "$MAX_TRIES" ]; do
    if php bin/console dbal:run-sql "SELECT 1" --no-interaction > /dev/null 2>&1; then
        DB_OK=1
        break
    fi
    TRIES=$((TRIES + 1))
    echo "Database not ready, retrying in 2s... (${TRIES}/${MAX_TRIES})"
    sleep 2
done

if [ "$DB_OK" -eq 1 ]; then
    echo "Database is ready."
    echo "Running migrations..."
    php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
else
    echo "WARNING: Database not reachable. Starting web server anyway (check DATABASE_URL on Railway)."
fi

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

echo "Starting Nginx on 0.0.0.0:${PORT}..."
exec nginx -g "daemon off;"
