FROM php:8.3-fpm AS builder

WORKDIR /app

# nag-install system dependencies and PHP extensions
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    curl \
    zlib1g-dev \
    libzip-dev \
    && docker-php-ext-install pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

# nag-install Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin \
    --filename=composer

# nag-allow Composer to run as superuser
ENV COMPOSER_ALLOW_SUPERUSER=1

# nag-copy Composer files first for dependency caching
COPY composer.json composer.lock ./

# nag-install PHP dependencies
RUN composer install --no-interaction --no-scripts --optimize-autoloader

# nag-copy the rest of the project files
COPY . .

# nag-minimal .env for image (real secrets/DB URL come from Railway or compose env_file)
RUN echo "APP_ENV=prod" > /app/.env && \
    echo "APP_DEBUG=0" >> /app/.env && \
    echo "APP_SECRET=ChangeMeInProduction" >> /app/.env

# nag-use production env during build (dev bundles are removed by --no-dev)
ENV APP_ENV=prod
ENV APP_DEBUG=0

# nag-run Symfony commands
RUN composer install --no-interaction --optimize-autoloader --no-ansi --no-dev --no-scripts

RUN php bin/console importmap:install --no-interaction --env=prod --no-debug

RUN php bin/console cache:warmup --env=prod --no-debug

RUN php bin/console asset-map:compile --env=prod --no-debug

# nag-runtime stage
FROM php:8.3-fpm AS runtime

ENV APP_ENV=prod
ENV APP_DEBUG=0
ENV PORT=80

WORKDIR /app

# nag-install required runtime packages and PHP extensions
RUN apt-get update && apt-get install -y \
    nginx \
    curl \
    && docker-php-ext-install pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

# nag-copy application files from builder stage
COPY --from=builder /app /app

# nag-create required directories and set permissions
RUN mkdir -p /app/var && \
    chown -R www-data:www-data /app && \
    chmod -R 755 /app && \
    chmod -R 775 /app/var

# nag-copy Nginx main configuration
COPY nginx-main.conf /etc/nginx/nginx.conf

# nag-remove default Nginx site configuration
RUN rm -rf /etc/nginx/conf.d/* \
    /etc/nginx/sites-enabled/* \
    /etc/nginx/sites-available/*

# nag-copy custom Nginx server block
COPY nginx.conf /etc/nginx/conf.d/default.conf

# nag-copy Docker entrypoint script
COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# nag-make entrypoint script executable
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# nag-healthcheck to verify the app is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD sh -c 'curl -f http://127.0.0.1:${PORT:-80}/ || exit 1'

# Expose HTTP port
EXPOSE 80

# Run the entrypoint script
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]