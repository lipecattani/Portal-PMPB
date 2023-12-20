# Use an official WordPress image as a base
FROM php:8.2-apache

# Switch to Debian base for additional package installation
FROM debian:bullseye

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash

# Install PHP extensions
RUN set -ex; \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    ; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        mysqli \
        zip \
    ; \
    pecl install imagick-3.6.0; \
    docker-php-ext-enable imagick; \
    rm -r /tmp/pear

# Set PHP.ini settings
RUN { \
    echo 'upload_max_filesize = 32M'; \
    echo 'post_max_size = 32M'; \
} > /usr/local/etc/php/conf.d/custom-php.ini

# WordPress setup
RUN set -ex; \
    version={{ .upstream | @sh }}; \
    sha1={{ .sha1 | @sh }}; \
    \
    curl -o wordpress.tar.gz -fL "https://wordpress.org/wordpress-$version.tar.gz"; \
    echo "$sha1 *wordpress.tar.gz" | sha1sum -c -; \
    \
    tar -xzf wordpress.tar.gz -C /usr/src/; \
    rm wordpress.tar.gz; \
    \
    mkdir -p /var/www/html; \
    chown -R www-data:www-data /var/www/html; \
    chown -R www-data:www-data /usr/src/wordpress; \
    \
    docker-php-ext-enable opcache; \
    { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=2'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
    \
    { \
        echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
        echo 'display_errors = Off'; \
        echo 'display_startup_errors = Off'; \
        echo 'log_errors = On'; \
        echo 'error_log = /dev/stderr'; \
        echo 'log_errors_max_len = 1024'; \
        echo 'ignore_repeated_errors = On'; \
        echo 'ignore_repeated_source = Off'; \
        echo 'html_errors = Off'; \
    } > /usr/local/etc/php/conf.d/error-logging.ini; \
    \
    { \
        echo '# BEGIN WordPress'; \
        echo ''; \
        echo 'RewriteEngine On'; \
        echo 'RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]'; \
        echo 'RewriteBase /'; \
        echo 'RewriteRule ^index\.php$ - [L]'; \
        echo 'RewriteCond %{REQUEST_FILENAME} !-f'; \
        echo 'RewriteCond %{REQUEST_FILENAME} !-d'; \
        echo 'RewriteRule . /index.php [L]'; \
        echo ''; \
        echo '# END WordPress'; \
    } > /usr/src/wordpress/.htaccess; \
    \
    mkdir -p /var/www/html/wp-content; \
    for dir in /usr/src/wordpress/wp-content/*/ cache; do \
        dir="$(basename "${dir%/}")"; \
        mkdir "/var/www/html/wp-content/$dir"; \
    done; \
    chown -R www-data:www-data /var/www/html/wp-content; \
    chmod -R 1777 /var/www/html/wp-content

VOLUME /var/www/html

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD [ "apache2-foreground" ]
