# selfoss 2.19 for Railway.
# Upstream publishes no Docker image (Docker Hub fossar/selfoss has no tags), so this
# builds the official release zip, checked against its sha256, on the official PHP image.
FROM php:8.2.36-apache-bookworm@sha256:bc98ca50e86358fc4f7c37b179a7edfacd6164663d3167925f0a0a85def09054

ARG SELFOSS_VERSION=2.19
ARG SELFOSS_SHA256=e49c4750e9723277963ca699b602f09f9148e2b9f258fce6b14429498af0e4fc

# GD (with JPEG, WebP, FreeType) is needed for favicons and thumbnails.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip libpng16-16 libjpeg62-turbo libfreetype6 libwebp7 \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev; \
    docker-php-ext-configure gd --with-jpeg --with-freetype --with-webp; \
    docker-php-ext-install -j2 gd; \
    apt-get purge -y --auto-remove libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev; \
    rm -rf /var/lib/apt/lists/*; \
    php -r 'exit(function_exists("imagecreatefromjpeg") && function_exists("imagecreatefromwebp") ? 0 : 1);'

RUN set -eux; \
    curl -fsSL -o /tmp/selfoss.zip "https://github.com/fossar/selfoss/releases/download/${SELFOSS_VERSION}/selfoss-${SELFOSS_VERSION}.zip"; \
    echo "${SELFOSS_SHA256}  /tmp/selfoss.zip" | sha256sum -c -; \
    unzip -q /tmp/selfoss.zip -d /tmp; \
    rm -rf /var/www/html; \
    mv /tmp/selfoss /var/www/html; \
    rm /tmp/selfoss.zip; \
    mv /var/www/html/data /opt/selfoss-data-skeleton; \
    mkdir /var/www/html/data; \
    chown -R www-data:www-data /var/www/html; \
    a2enmod -q rewrite headers expires; \
    a2dismod -q -f autoindex status; \
    a2dissite -q 000-default

COPY apache-selfoss.conf /etc/apache2/conf-available/zz-selfoss.conf
COPY start.sh /usr/local/bin/selfoss-start
RUN a2enconf -q zz-selfoss && chmod 755 /usr/local/bin/selfoss-start

# Railway volume: /var/www/html/data (SQLite database, favicons, thumbnails, sessions).
ENV PORT=8080
EXPOSE 8080
STOPSIGNAL SIGTERM
CMD ["/usr/local/bin/selfoss-start"]
