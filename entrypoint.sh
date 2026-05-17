#!/bin/sh
set -e

echo "Waiting for database..."
until php bin/console dbal:run-sql "SELECT 1" --no-interaction > /dev/null 2>&1; do
    echo "Database not ready, retrying in 2s..."
    sleep 2
done
echo "Database is ready."

echo "Running migrations..."
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

if [ "$APP_ENV" = "prod" ]; then
    echo "Clearing production cache..."
    php bin/console cache:clear --env=prod --no-debug
    echo "Compiling assets..."
    php bin/console asset-map:compile --env=prod --no-debug
fi

echo "Fixing var directory permissions..."
chown -R www-data:www-data /app/var

echo "Starting PHP-FPM..."
php-fpm -D

echo "Starting Nginx..."
exec nginx -g "daemon off;"
