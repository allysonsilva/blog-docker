ARG APP_FOLDER=.
ARG DOCKER_FOLDER=./docker
ARG PHP_BASE_IMAGE_VERSION=8.2-cli-alpine

#####
## COMPOSER
#####

FROM composer:2.5 as vendor

WORKDIR /app

ENV COMPOSER_HOME /composer

ARG APP_FOLDER

# Copy only the files needed to download dependencies to avoid redownloading them when our code changes
COPY $APP_FOLDER/composer.json composer.json
# COPY $APP_FOLDER/composer.lock composer.lock

RUN set -xe \
    &&  composer install \
            --optimize-autoloader \
            --ignore-platform-reqs \
            --prefer-dist \
            --ansi \
            --no-dev \
            --profile \
            --no-cache \
            --no-scripts \
            --no-interaction

#####
## FRONTEND
#####

FROM node:18-alpine as frontend

WORKDIR /app

ARG APP_FOLDER

COPY $APP_FOLDER/package.json ./

RUN set -xe \
    && npm install

#####
## PHP EXTENSIONS + DEPENDENCIES
#####

FROM php:$PHP_BASE_IMAGE_VERSION as dependencies

RUN set -xe; \
    \
    echo "---> Installing PHP Extensions"; \
    \
    apk update; \
    \
    apk add --no-cache --virtual .build-deps \
        # for sockets
        linux-headers \
        # \
        $PHPIZE_DEPS \
        curl-dev \
        pcre-dev \
        # SQLite3
        sqlite-dev \
        # for intl extension
        icu-dev \
        # for GD
        freetype-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        libwebp-dev \
        # for zip extension
        zlib-dev \
        libzip-dev \
        gnutls-dev \
        # for gpm extension
        gmp-dev \
        # for soap
        libxml2-dev \
        # for amqp
        rabbitmq-c-dev \
    ; \
    apk add --no-cache --virtual .persistent-deps \
        vim \
        # for intl
        icu-libs \
        # for mongodb
        libssl1.1 \
        # for zip
        libzip \
        # for gpm
        gmp \
    ; \
    docker-php-ext-configure gd \
        --enable-gd \
        --with-jpeg \
        --with-webp \
        --with-freetype \
    ; \
    docker-php-ext-configure mysqli --with-mysqli=mysqlnd && \
    docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd && \
    docker-php-ext-configure zip --with-zip && \
    docker-php-ext-install -j $(nproc) \
        exif \
        intl \
        gd \
        gmp \
        pcntl \
        mysqli \
        pdo_mysql \
        soap \
        sockets \
        opcache \
        zip \
        bcmath \
        calendar \
    ; \
    pecl install -o -f \
        ds-1.4.0 \
        amqp-1.11.0 \
        mongodb-1.15.1 \
        excimer-1.1.1 \
    ; \
        pecl install -o -f -D 'enable-sockets="yes" enable-openssl="yes" enable-http2="yes" enable-mysqlnd="yes" enable-swoole-json="yes" enable-swoole-curl="yes" enable-cares="no"' swoole-5.0.2 \
    ; \
    \
    # Igbinary: Is a drop in replacement for the standard php serializer.
    pecl install -o -f \
        igbinary-3.2.14 \
    ; \
    # redis/configure \
    #       --with-php-config=/usr/local/bin/php-config \
    #       --enable-redis-igbinary=yes \
    #       --enable-redis-lzf=no \
    #       --enable-redis-zstd=no
    printf "yes \n no \n no \n" | pecl install redis-5.3.7 \
    ; \
    docker-php-ext-enable \
        ds \
        amqp \
        swoole \
        igbinary \
        redis \
        mongodb \
        excimer \
    ; \
    php --version \
    ; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache $runDeps; \
    apk del --no-network .build-deps; \
    rm -rf /tmp/* /var/cache/apk/*

RUN set -xe; \
    \
    echo "---> Installing Packages Dependencies"; \
    \
    apk update; \
    \
    apk add --update --no-cache \
        fd \
        exa \
        git \
        sudo \
        curl \
        wget \
        make \
        bash \
        tini \
        nodejs \
        npm \
        bind-tools \
        supervisor \
        mysql-client \
        mariadb-connector-c \
        busybox-suid \
        openssh-client \
        bash-completion; \
    \
    rm -rf /tmp/* /var/cache/apk/*

#####
## APP CONTAINER
#####

FROM dependencies as main

ARG APP_FOLDER
ARG DOCKER_FOLDER

# = /usr/local/etc/php
ENV PHP_INI_DIR ${PHP_INI_DIR:-/usr/local/etc/php}
# = /usr/local/etc/php/conf.d
ENV PHP_INI_SCAN_DIR ${PHP_INI_DIR}/conf.d
# Default PATH LOG
ENV LOG_PATH=/usr/local/var/log
# Path logs PHP
ENV PHP_LOG_PATH=$LOG_PATH/php

# Default directory for application deployment
# Location of the folder in the container, path of the folder inside the container
ARG REMOTE_SRC=/var/www/app
ENV REMOTE_SRC $REMOTE_SRC

# Image user
ARG USER_NAME=app
ENV USER_NAME $USER_NAME

ARG USER_UID=1000
ARG USER_GID=1000

# Path docker PHP/APP folder
# Path Config/Dockerfile PHP/APP
ARG LOCAL_DOCKER_PHP_PATH=$DOCKER_FOLDER/php
ENV LOCAL_DOCKER_PHP_PATH $LOCAL_DOCKER_PHP_PATH

ARG LOCAL_DOCKER_MYSQL_PATH=$DOCKER_FOLDER/mysql
ARG LOCAL_DOCKER_MYSQL_SSL_PATH=$LOCAL_DOCKER_MYSQL_PATH/ssl

ARG APP_FOLDER
ENV APP_FOLDER $APP_FOLDER

# app || queue || scheduler
ARG CONTAINER_ROLE=app
ENV CONTAINER_ROLE $CONTAINER_ROLE

ARG APP_ENV=production
ENV APP_ENV ${APP_ENV:-production}

#####
## CONFIGURATIONS
#####

COPY $LOCAL_DOCKER_PHP_PATH/configs/conf.d/opcache.ini $PHP_INI_SCAN_DIR/docker-php-ext-opcache.ini

# /usr/local/etc/php/php.ini
COPY $LOCAL_DOCKER_PHP_PATH/configs/php-$APP_ENV.ini $PHP_INI_DIR/php.ini

# SUPERVISOR CONF's
COPY $LOCAL_DOCKER_PHP_PATH/configs/queue/supervisord.conf /etc/supervisor/supervisord.conf
COPY $LOCAL_DOCKER_PHP_PATH/configs/queue/templates/* /etc/supervisor/conf.d/

RUN set -xe \
    && mkdir -p $PHP_LOG_PATH $LOG_PATH/supervisor && touch $PHP_LOG_PATH/php.errors.log

RUN set -xe \
    && PHP_ERROR="$( php -v 2>&1 1>/dev/null )" \
    && if [ -n "$PHP_ERROR" ]; then echo "$PHP_ERROR"; false; fi \
    && php -m; php -v; php --ini \
    && php -i | grep -E '^opcache\.(enable_cli|jit|jit_buffer_size) '

RUN if [ "$USER_UID" != 1000 ]; then \
        set -xe \
        && echo "---> Adding the www-data(1000) user" \
        && deluser --remove-home www-data \
        && delgroup www-data || true \
        && addgroup --gid 1000 www-data \
        && adduser --gecos "" --disabled-password --uid 1000 --ingroup www-data --shell /bin/bash www-data \
        && echo "www-data ALL = (ALL) NOPASSWD: ALL" >> /etc/sudoers \
        && chown -R www-data:www-data /home/www-data \
    ;fi

RUN set -xe \
    && echo "---> Adding USER to IMAGE" \
    && addgroup --gid ${USER_GID:-1000} $USER_NAME \
    && adduser --gecos "" --disabled-password --uid ${USER_UID:-1000} --ingroup $USER_NAME --shell /bin/bash $USER_NAME \
    && echo "$USER_NAME ALL = (ALL) NOPASSWD: ALL" >> /etc/sudoers \
    # Replace it with /bin/bash:
    && sed -i "/root/s/bin\/ash/bin\/bash/g" /etc/passwd

RUN if [ ! -d "$REMOTE_SRC" ]; then \
        mkdir -p /tmp/php /tmp/php/sessions /tmp/php/uploads $REMOTE_SRC $REMOTE_SRC/database/certs/mysql \
    ;fi

COPY $LOCAL_DOCKER_MYSQL_SSL_PATH/ca.pem $REMOTE_SRC/database/certs/mysql/
COPY $LOCAL_DOCKER_MYSQL_SSL_PATH/client-key.pem $REMOTE_SRC/database/certs/mysql/
COPY $LOCAL_DOCKER_MYSQL_SSL_PATH/client-cert.pem $REMOTE_SRC/database/certs/mysql/

RUN set -xe \
    && rm -rf /tmp/pear ~/.pearrc \
    && rm -rf /var/www/html

RUN set -xe; \
    \
    # ps -ef | grep cron | grep -v grep
    echo "---> Create Cron Files"; \
    \
    touch /var/log/cron.log; \
    \
    mkdir -p /var/spool/cron/crontabs; \
    \
    touch /var/spool/cron/crontabs/$USER_NAME

RUN set -xe \
    && echo "---> Changing Permissions" \
    && chown -R $USER_NAME:$USER_NAME \
        /usr/local/etc \
        /var/run /var/run/ \
        /usr/local/var/run \
        /home/${USER_NAME} \
        $LOG_PATH \
        /var/log \
        /tmp/php

# ENTRYPOINT
COPY $LOCAL_DOCKER_PHP_PATH/docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

#####
## APPLICATION
#####

# Application directory
WORKDIR $REMOTE_SRC

# Define the running USER
USER $USER_NAME

# Remove folder docker
RUN     if [ -d ${DOCKER_FOLDER} ]; then \
            rm -rf ${DOCKER_FOLDER} \
        ;fi

RUN set -xe \
    && echo "---> Installing Composer" \
    && COMPOSER_HOME="/home/${USER_NAME}/.composer/" \
    && curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer --version=2.5.4

# Environment variables
# Default: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PATH="$PATH:/home/${USER_NAME}/.composer/vendor/bin"

## Copy the downloaded dependencies from the {vendor} stage
COPY --chown=$USER_NAME:$USER_NAME --from=vendor /app/vendor/ ./vendor/
COPY --chown=$USER_NAME:$USER_NAME --from=vendor /app/composer.json ./composer.json
COPY --chown=$USER_NAME:$USER_NAME --from=vendor /app/composer.lock ./composer.lock

COPY --chown=$USER_NAME:$USER_NAME --from=frontend /app/node_modules ./node_modules

# Files APP
# Copy our application
COPY --chown=$USER_NAME:$USER_NAME $APP_FOLDER $REMOTE_SRC

RUN sudo mkdir -p   storage/logs \
                    storage/app/public \
                    storage/framework/cache \
                    storage/framework/sessions \
                    storage/framework/views

RUN set -xe \
    && DEFAULT_PARAMETERS_FD="--threads $(nproc) --hidden --no-ignore --ignore-case --show-errors" \
    && DEFAULT_EXCLUDE_FD='--exclude public -E .git -E vendor -E node_modules' \
    # -E, --exclude <pattern>... Exclude files/directories that match the given glob pattern
    # -E "{**/fileX,**/fileY}"
    # -E "{folderX,folderY}"
    && sudo fd $DEFAULT_EXCLUDE_FD $DEFAULT_PARAMETERS_FD --type directory --exec chmod 755 {} \; . $REMOTE_SRC \
    && sudo fd $DEFAULT_EXCLUDE_FD $DEFAULT_PARAMETERS_FD --type file --exec chmod 644 {} \; . $REMOTE_SRC \
    && sudo chgrp -R $USER_NAME storage bootstrap/cache \
    && sudo chmod -R ug+rwx storage bootstrap/cache

RUN set -xe \
    && php artisan optimize:clear --ansi || true \
    \
    && composer run-script post-autoload-dump || true \
    && composer run-script post-root-package-install || true \
    && composer run-script post-create-project-cmd || true \
    && composer dump-autoload --optimize --classmap-authoritative --no-dev --ansi || true

RUN set -xe \
    && php artisan view:clear \
    && php artisan route:clear \
    && php artisan config:clear \
    && php artisan storage:link \
    && php artisan clear-compiled \
    && exa --all --group --header --links --long --accessed --modified --git --icons --color=always

VOLUME ${LOG_PATH}

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]

# # Override stop signal to stop process gracefully
# STOPSIGNAL SIGQUIT

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
        echo 'session.use_strict_mode = 1'; \
        echo 'session.use_cookies = 1'; \
        echo 'session.cookie_secure = 1'; \
        echo 'session.use_only_cookies = 1'; \
        echo 'session.cookie_httponly = 1'; \
        echo 'session.cookie_samesite = "Strict"'; \
    } > /usr/local/etc/php/conf.d/zz-session-strict.ini

EXPOSE 4000 8080 8000 9005

# vim:set ft=dockerfile:
