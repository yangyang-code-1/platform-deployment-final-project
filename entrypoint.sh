#!/bin/sh

PORT="${PORT:-80}"
echo "=== Container startup (PORT=${PORT}, APP_ENV=${APP_ENV}) ==="

if [ -n "$RAILWAY_ENVIRONMENT" ]; then
    echo "Railway detected."
    if [ -z "$DATABASE_URL" ]; then
        echo "ERROR: DATABASE_URL is not set. On the app service, add DATABASE_URL referencing MySQL."
    else
        echo "DATABASE_URL is set."
    fi
    unset MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE MYSQL_ROOT_PASSWORD 2>/dev/null || true
fi

NGINX_CONF="/etc/nginx/conf.d/default.conf"
if [ "$PORT" != "80" ]; then
    echo "Configuring Nginx on 0.0.0.0:${PORT} and 0.0.0.0:80 (Railway proxy may use either)..."
    sed -i "s/listen 0.0.0.0:80 default_server;/listen 0.0.0.0:${PORT} default_server;\n    listen 0.0.0.0:80 default_server;/" "$NGINX_CONF"
else
    echo "Configuring Nginx to listen on 0.0.0.0:${PORT}..."
    sed -i "s/listen 0.0.0.0:80/listen 0.0.0.0:${PORT}/" "$NGINX_CONF"
fi

DB_OK=0
TRIES=0
MAX_TRIES=30
echo "Waiting for database..."
while [ "$TRIES" -lt "$MAX_TRIES" ]; do
    if php bin/console dbal:run-sql "SELECT 1" --no-interaction > /dev/null 2>&1; then
        DB_OK=1
        break
    fi
    TRIES=$((TRIES + 1))
    echo "Database not ready (${TRIES}/${MAX_TRIES})..."
    sleep 2
done

if [ "$DB_OK" -eq 1 ]; then
    echo "Database is ready."
    php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || echo "Migrations skipped or failed (non-fatal)."
else
    echo "WARNING: Database not reachable. Web server will still start."
fi

if [ "$APP_ENV" = "prod" ]; then
    php bin/console cache:warmup --env=prod --no-debug || echo "Cache warmup failed (non-fatal)."
    if [ ! -f public/assets/manifest.json ]; then
        php bin/console asset-map:compile --env=prod --no-debug || echo "Asset compile failed (non-fatal)."
    fi
fi

chown -R www-data:www-data /app/var 2>/dev/null || true

echo "Starting PHP-FPM..."
php-fpm -D

echo "Starting Nginx..."
exec nginx -g "daemon off;"
