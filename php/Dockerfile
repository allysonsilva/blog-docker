ARG APP_FOLDER=.
ARG COMPOSER_VERSION=2.7
ARG DOCKER_FOLDER=./docker
ARG PHP_BASE_IMAGE_VERSION=8.3-zts-alpine
ARG FRANKENPHP_VERSION=1.1-php8.3-alpine

# @see https://github.com/exaco/laravel-octane-dockerfile/blob/main/FrankenPHP.Dockerfile
# @see https://github.com/dunglas/frankenphp/blob/main/alpine.Dockerfile

#####
## SERVER
#####

FROM dunglas/frankenphp:${FRANKENPHP_VERSION} AS server

#####
## COMPOSER
#####

FROM composer:${COMPOSER_VERSION} as vendor

WORKDIR /app

ENV COMPOSER_HOME /composer

ARG APP_FOLDER

COPY $APP_FOLDER .

RUN set -xe \
    &&  composer install \
        --optimize-autoloader \
        --ignore-platform-reqs \
        --prefer-dist \
        --no-progress \
        --no-dev \
        --no-cache \
        --no-interaction \
        --ansi

#####
## FRONTEND
#####

FROM node:21-alpine as frontend

ARG APP_FOLDER

ENV ROOT=/app

WORKDIR ${ROOT}

RUN npm config set update-notifier false && npm set progress=false

COPY $APP_FOLDER/package*.json ./

RUN set -xe \
    && npm install --loglevel=error --no-audit

#####
## PHP
#####

FROM php:$PHP_BASE_IMAGE_VERSION as dependencies

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

RUN set -xe; \
    \
    echo "---> Installing PHP Extensions"; \
    \
    apk update; \
    \
    apk add --no-cache --virtual .phpize-deps $PHPIZE_DEPS && \
    docker-php-ext-configure mysqli --with-mysqli=mysqlnd && \
    docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd && \
    install-php-extensions \
        gd \
        zip \
        gmp \
        intl \
        soap \
        exif \
        pcntl \
        bcmath \
        mysqli \
        sockets \
        opcache \
        pdo_mysql \
        ds-^1 \
        amqp-^2.1@stable \
        mongodb-^1.17@stable \
        igbinary-^3.2@stable \
        msgpack-^2.2@stable \
        redis-^6@stable \
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
    apk del --no-network .phpize-deps; \
    docker-php-source delete; \
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
        vim \
        npm \
        sudo \
        curl \
        wget \
        make \
        bash \
        tini \
        nodejs \
        tzdata \
        libcap \
        bind-tools \
        supervisor \
        mysql-client \
        busybox-suid \
        openssh-client \
        bash-completion; \
    \
    rm -rf /tmp/* /var/cache/apk/*

#####
## APP CONTAINER
#####

FROM dependencies as main

LABEL maintainer="Alyson Silva <hello@alysonsilva.dev>"
LABEL org.opencontainers.image.title="alysonsilva.dev Laravel Octane Dockerfile"
LABEL org.opencontainers.image.description="Docker my personal blog using octane Laravel Octane"
LABEL org.opencontainers.image.source=https://github.com/allysonsilva/blog-docker
LABEL org.opencontainers.image.licenses=MIT

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

COPY $LOCAL_DOCKER_PHP_PATH/configs/conf.d/* $PHP_INI_SCAN_DIR/

# /usr/local/etc/php/php.ini
COPY $LOCAL_DOCKER_PHP_PATH/configs/php-$APP_ENV.ini $PHP_INI_DIR/php.ini

# SUPERVISOR CONF's
COPY $LOCAL_DOCKER_PHP_PATH/configs/queue/supervisord.conf /etc/supervisor/supervisord.conf
COPY $LOCAL_DOCKER_PHP_PATH/configs/queue/templates/* /etc/supervisor/conf.d/

RUN set -xe \
    && mkdir -p $PHP_LOG_PATH $LOG_PATH/supervisor && touch $PHP_LOG_PATH/php.errors.log

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

COPY --chown=${USER_NAME}:${USER_NAME} --from=vendor /usr/bin/composer /usr/local/bin/composer

RUN set -xe \
    && echo "---> Installing Composer" \
    && COMPOSER_HOME="/home/${USER_NAME}/.composer/" \
    # && curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer --version=2.7.0 \
    && sudo chown ${USER_NAME}:${USER_NAME} /usr/local/bin/composer

# Environment variables
# Default: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PATH="$PATH:/home/${USER_NAME}/.composer/vendor/bin"

# Files APP
COPY --chown=${USER_NAME}:${USER_NAME} --from=vendor /app/ $REMOTE_SRC
COPY --chown=${USER_NAME}:${USER_NAME} --from=frontend /app/node_modules $REMOTE_SRC/node_modules

RUN sudo mkdir -p   storage/logs \
                    storage/app/public \
                    storage/framework/{sessions,views,cache}

RUN set -xe \
    && echo "---> Changing Permissions" \
    && sudo chown -R $USER_NAME:$USER_NAME \
        /usr/local/etc \
        /var/run \
        /var/log \
        /usr/local/var/run \
        /home/${USER_NAME} \
        $LOG_PATH \
        /tmp/php

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
    && php artisan view:clear \
    && php artisan route:clear \
    && php artisan config:clear \
    && php artisan storage:link \
    && exa --all --group --header --links --long --accessed --modified --git --icons --color=always

COPY --chown=$USER_NAME:$USER_NAME --from=server /usr/local/bin/frankenphp /usr/local/bin/frankenphp

RUN sudo setcap cap_net_bind_service=+ep /usr/local/bin/frankenphp

RUN set -xe \
    && PHP_ERROR="$( php -v 2>&1 1>/dev/null )" \
    && if [ -n "$PHP_ERROR" ]; then echo "$PHP_ERROR"; false; fi \
    && php -m; php -v; php --ini \
    && php -i | grep -E '^opcache\.(enable_cli|jit|jit_buffer_size) ' \
    && composer --version \
    && frankenphp version

VOLUME ${LOG_PATH}

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]

EXPOSE 80 443 443/udp 2019 8000

# vim:set ft=dockerfile:
