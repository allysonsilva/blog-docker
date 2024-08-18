#!/usr/bin/env bash

set -e

printf "\n\033[34m--- [$CONTAINER_ROLE] ENTRYPOINT APP --- \033[0m\n"

# Convert to UPPERCASE
CONTAINER_ROLE=${CONTAINER_ROLE^^}

if [ -z "$APP_ENV" ]; then
    printf "\n\033[31m[$CONTAINER_ROLE] A \$APP_ENV environment is required to run this container!\033[0m\n"
    exit 1
fi

if [ -z "$APP_KEY" ]; then
    printf "\n\033[31m[$CONTAINER_ROLE] A \$APP_KEY environment is required to run this container!\033[0m\n"
    exit 1
fi

shopt -s dotglob
sudo chown -R ${USER_NAME}:${USER_NAME} \
        /home/${USER_NAME} \
        /usr/local/var/run \
        /var/run \
        /var/log \
        /tmp/php \
        $LOG_PATH
shopt -u dotglob

sudo find /usr/local/etc ! -name "php.ini" | xargs -I {} chown ${USER_NAME}:${USER_NAME} {}

configure_php_ini() {
    sed -i \
        -e "s/memory_limit.*$/memory_limit = ${PHP_MEMORY_LIMIT:-128M}/g" \
        -e "s/max_execution_time.*$/max_execution_time = ${PHP_MAX_EXECUTION_TIME:-30}/g" \
        -e "s/max_input_time.*$/max_input_time = ${PHP_MAX_INPUT_TIME:-30}/g" \
        -e "s/post_max_size.*$/post_max_size = ${PHP_POST_MAX_SIZE:-8M}/g" \
        -e "s/upload_max_filesize.*$/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-2M}/g" \
    \
    $PHP_INI_DIR/php.ini

    # # @see https://github.com/dunglas/frankenphp/issues/309
    # sed -i \
    #     -e '/opcache.jit_buffer_size/s/^; //g' \
    #     -e '/opcache.jit/s/^; //g' \
    # \
    # $PHP_INI_SCAN_DIR/99-opcache.ini

    # { \
    #     echo 'session.use_strict_mode = 1'; \
    # } > $PHP_INI_SCAN_DIR/zz-session-strict.ini
}

install_composer_dependencies() {
    if [ ! -d "vendor" ] && [ -f "composer.json" ]; then
        printf "\n\033[33mComposer vendor folder was not installed. Running >_ composer install --prefer-dist --no-interaction --optimize-autoloader --ansi\033[0m\n\n"

        composer install --prefer-dist --no-interaction --optimize-autoloader --ignore-platform-reqs --ansi

        printf "\n\033[33mcomposer run-script post-root-package-install\033[0m\n\n"

        composer run-script post-root-package-install

        printf "\n\033[33mcomposer run-script post-autoload-dump\033[0m\n\n"

        composer run-script post-autoload-dump
    fi
}

common_entrypoint() {
    php artisan app:generate-feed || true
    php artisan app:generate-sitemap || true

    npm --section=site run mix-production || true

    php artisan app:generate-partials-shell --no-interaction || true

    npm run workbox-precache || true

    npm --section=combine run mix-production || true
}

# $> {view:clear} && {cache:clear} && {route:clear} && {config:clear} && {clear-compiled}
# @see https://github.com/laravel/framework/blob/9.x/src/Illuminate/Foundation/Console/OptimizeClearCommand.php
if [[ -d "vendor" && ${FORCE_CLEAR:-true} == true ]]; then
    printf "\n\033[33mLaravel - artisan view:clear + route:clear + config:clear + clear-compiled\033[0m\n\n"

    php artisan event:clear || true
    php artisan view:clear
    php artisan route:clear
    php artisan config:clear
    php artisan clear-compiled
fi

if [[ -d "vendor" && ${CACHE_CLEAR:-false} == true ]]; then
    printf "\n\033[33mLaravel - artisan cache:clear\033[0m\n\n"

    php artisan cache:clear 2>/dev/null || true
fi

if [[ -d "vendor" && ${FORCE_OPTIMIZE:-true} == true ]]; then
    printf "\n\033[33mLaravel Cache Optimization - artisan config:cache + route:cache + view:cache\033[0m\n\n"

    # $> {config:cache} && {route:cache}
    # @see https://github.com/laravel/framework/blob/9.x/src/Illuminate/Foundation/Console/OptimizeCommand.php
    php artisan optimize || true
    php artisan view:cache || true
    php artisan event:cache || true
fi

if [[ -d "vendor" && ${FORCE_MIGRATE:-false} == true ]]; then
    printf "\n\033[33mLaravel - artisan migrate --force\033[0m\n\n"

    php artisan migrate --force || true
fi

if [[ ${FORCE_STORAGE_LINK:-true} == true ]]; then
    printf "\n\033[33mLaravel - artisan storage:link\033[0m\n\n"

    rm -rf ${REMOTE_SRC}/public/storage || true
    php artisan storage:link || true
fi

if [[ ${OPCACHE_ENABLED:-true} == false ]]; then
    rm -f ${PHP_INI_SCAN_DIR}/opcache.ini >/dev/null 2>&1 || true
    rm -f ${PHP_INI_SCAN_DIR}/docker-php-ext-opcache.ini >/dev/null 2>&1 || true
fi

if [ "$APP_ENV" = "production" ]; then
    configure_php_ini
fi

install_composer_dependencies

echo
php -v
echo
php --ini

if [ "$CONTAINER_ROLE" = "APP" ]; then
    common_entrypoint

    printf "\033[34m[$CONTAINER_ROLE] Running with Laravel Octane ...\033[0m\n"

    sudo mv /etc/supervisor/conf.d/laravel-octane.conf.tpl /etc/supervisor/conf.d/laravel-octane.conf

    exec /usr/bin/supervisord --nodaemon --configuration /etc/supervisor/supervisord.conf

elif [ "$CONTAINER_ROLE" = "QUEUE" ]; then

    printf "\n\033[34m[$CONTAINER_ROLE] Running the [QUEUE-WORKER] Service ...\033[0m\n"

    fileWorkerTpl=/etc/supervisor/conf.d/laravel-worker.conf.tpl

    sudo sed -i \
            -e "s|{{USER_NAME}}|$USER_NAME|g" \
            -e "s|{{REMOTE_SRC}}|${REMOTE_SRC}|g" \
            -e "s|{{REDIS_QUEUE}}|${REDIS_QUEUE:-default}|g" \
            -e "s|{{QUEUE_CONNECTION}}|${QUEUE_CONNECTION:-redis}|g" \
            -e "s|{{QUEUE_TIMEOUT}}|${QUEUE_TIMEOUT:-60}|g" \
            -e "s|{{QUEUE_MEMORY}}|${QUEUE_MEMORY:-64}|g" \
            -e "s|{{QUEUE_TRIES}}|${QUEUE_TRIES:-3}|g" \
            -e "s|{{QUEUE_BACKOFF}}|${QUEUE_BACKOFF:-3}|g" \
            -e "s|{{QUEUE_SLEEP}}|${QUEUE_SLEEP:-10}|g" ${fileWorkerTpl} \
    \
    && sudo mv $fileWorkerTpl /etc/supervisor/conf.d/laravel-worker.conf

    printf "\n\033[34m[$CONTAINER_ROLE] Starting [SUPERVISOR] ... \033[0m\n\n"

    exec /usr/bin/supervisord --nodaemon --configuration /etc/supervisor/supervisord.conf

    # # Reload the daemon's configuration files
    # supervisorctl -c /etc/supervisor/supervisord.conf reread
    # # Reload config and add/remove as necessary
    # supervisorctl -c /etc/supervisor/supervisord.conf update
    # # Start all processes of the group "laravel-worker"
    # supervisorctl -c /etc/supervisor/supervisord.conf start laravel-worker:*

    # # Since queue workers are long-lived processes, they will not notice changes to your code without being restarted.
    # # So, the simplest way to deploy an application using queue workers is to restart the workers during your deployment process.
    # # You may gracefully restart all of the workers by issuing the queue:restart command:
    #
    # # This command will instruct all queue workers to gracefully exit after they finish processing their current job so that no existing jobs are lost.
    # php artisan queue:restart

elif [ "$CONTAINER_ROLE" = "SCHEDULER" ]; then

    if ! sudo grep -q "\/artisan schedule:run" /etc/crontabs/${USER_NAME}; then
        printf "\n\033[33mAdding >_ php artisan schedule:run >> /dev/null 2>&1 command to crond\033[0m\n"

        # https://crontab.guru/every-minute
        sudo crontab -l -u $USER_NAME | { cat; echo "* * * * * /usr/local/bin/php ${REMOTE_SRC}/artisan schedule:run --no-ansi >> ${REMOTE_SRC}/storage/logs/scheduler.log 2>&1"; } | sudo crontab -u $USER_NAME -
    fi

    # It must be used so that CRON can use the values of the environment variables
    # The CRON service can not retrieve all environment variables, especially those defined in the docker-compose.yml file, when the line below is not set
    sudo printenv > /etc/environment

    sudo sed -i -e "s|{{REMOTE_SRC}}|${REMOTE_SRC}|g" /etc/crontabs/${USER_NAME}
    sudo sed -i -e "s|{{REMOTE_SRC}}|${REMOTE_SRC}|g" /var/spool/cron/crontabs/$USER_NAME

    printf "\n\033[34m[$CONTAINER_ROLE] Starting [SCHEDULE] Service ...\033[0m\n\n"

    exec /usr/sbin/crond -l 2 -f -L /var/log/cron.log
fi

exec "$@"
