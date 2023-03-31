#!/usr/bin/env bash

# time ./scripts/deploy-new-version.sh

# This will cause the script to exit on the first error
set -e

if ! [ -x "$(command -v docker)" ]; then
    printf "\n\033[31m[DEPLOY] ERROR: docker is not installed!\033[0m\n\n" >&2
    exit 1
fi

set -o allexport
[[ -f deploy.env ]] && source deploy.env
[[ -f .env ]] && source .env
set +o allexport

container_state()
{
    local options containers=() timeout=90

    # options may be followed by one colon to indicate they have a required argument
    if ! options=$(getopt --longoptions "containers:,timeout::" --options "c:t::" --alternative -- "$@")
    then
        # something went wrong, getopt will put out an error message for us
        exit 1
    fi

    if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

    eval set -- "$options"

    while [ $# -gt 0 ]; do
        case $1 in
            --containers) shift ; IFS=' ' read -r -a containers <<< "$1" ;;
            --timeout) timeout="$2" ; shift;;
            # (-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
            (*) break;;
        esac
        shift
    done

    if [[ "$(declare -p containers)" =~ "declare -a" && ${#containers[@]} -gt 0 ]]; then

        for containerName in ${containers[@]}; do

            # Set timeout to the number of seconds you are willing to wait
            timeoutIn=$timeout; counter=0

            printf "\n\033[3;33m[DEPLOY] Esperando healthcheck do container docker \"${containerName}\" = \"healthy\" ⏳ \033[0m\n"

            # This says that until docker inspect reports the container is in a running state, keep looping
            until [[ "$(docker container inspect -f '{{.State.Health.Status}}' ${containerName})" == "healthy" &&
                      $(docker container inspect --format '{{json .State.Running}}' $containerName) == true ]]; do

                # If we've reached the timeout period, report that and exit to prevent running an infinite loop
                if [[ $timeoutIn -lt $counter ]]; then
                    echo
                    docker logs $containerName

                    printf "\n\033[1;31m[DEPLOY] ERROR: Timed out waiting for ${containerName} to come up/healthy ❌\033[0m\n\n"
                    exit 1
                fi

                # Every 5 seconds update the status
                if (( $counter % 5 == 0 )); then
                    printf "\n\033[35m[DEPLOY] Waiting for $containerName to be ready/healthy (${counter}/${timeoutIn}) ⏱ \033[0m\n"
                fi

                # Wait a second and increment the counter
                sleep 1s
                counter=$((counter + 1))
            done

            printf "\n\033[43;3;30m[DEPLOY] Serviço Docker \"${containerName}\" adicionado e Healthcheck validado com sucesso(UP) 🚀\033[0m\n"

        done

    else
        printf "\n\033[1;31m[DEPLOY] ERROR: Nenhum container pôde ser encontrado na opção \`--containers\` ❌\033[0m\n\n"
        exit 1
    fi

    (( $? == 0 )) || return
}

usage()
{
    echo -e "Usage: \033[3m$0\033[0m [ -v=|--new-version= ]" 1>&2
    echo -e "\t\t\t\t       [ -n|--num-app-scale= ]" 1>&2
    echo -e "\t\t\t\t       [ -d=|--app-docker-image= ]" 1>&2

    echo
    echo -e "\t\033[3;32m-h, -help,             --help\033[0m
                    Display help"

    echo
    echo -e "\t\033[3;32m-v, -new-version,      --new-version\033[0m
                    - Nova versão utilizada como prefixo dos containers da aplicação
                    - \033[3mUtilizando o padrão: \033[1m{COMPOSE_PROJECT_NAME}-CONTAINER_NAME-v{NUM_VERSAO}-{NUM_SCALE}\033[0m\033[0m
                    \033[1mDefault\033[0m: \033[3;32mletra \"v\" concatenado com a soma do {número da versão antiga + 1}\033[0m"

    echo
    echo -e "\t\033[3;32m-n ,-num-app-scale,        --num-app-scale\033[0m
                    - Número total de containers que serão inicializados no contexto do \033[1mAPP/PHP\033[0m
                    - \033[3mEsses containers serão utilizados no balanceamento de carga do Traefik!\033[0m
                    \033[1mDefault\033[0m: \033[3;32mNúmero total de container em execução atualmente\033[0m"

    echo
    echo -e "\t\033[3;32m-d, -app-docker-image,      --app-docker-image\033[0m
                    - Imagem docker que será utilizada no \033[1m$> docker pull\033[0m do container da aplicação
                    \033[1mDefault\033[0m: \033[3;32mVariável de ambiente definido em \$APP_DOCKER_IMAGE\033[0m"

    echo
    echo -e "\t \033[1mExemplos:\033[0m"
    echo -e "\t     $0 -vv10 -n2 -d\"app/app:2.0\""
    echo -e "\t     $0 --new-version=11 --num-app-scale=2 --app-docker-image=\"app/app:2.0\""

    exit 0
}

# [ $# -eq 0 ] && usage

# [$@ Is all command line parameters passed to the script]
# --options is for short options like -v
# --longoptions is for long options with double dash like --version
# [The comma separates different long options]
# --alternative is for long options with single dash like -version
options=$(getopt --longoptions "help,new-version::,num-app-scale::,app-docker-image::" --options "v::n::i::" --alternative -- "$@")

if [ $? != 0 ] ; then echo -e "\n Terminating..." >&2 ; exit 1 ; fi

# set --:
# If no arguments follow this option, then the positional parameters are unset. Otherwise, the positional parameters
# are set to the arguments, even if some of them begin with a '-'
eval set -- "$options"

printf "\n"
printf "\033[34m======================================\033[0m\n"
printf "\033[34m============== [DEPLOY] ==============\033[0m\n"
printf "\033[34m======================================\033[0m\n"

printf "\n\033[36m[DEPLOY] Script started on $(date +"%d/%m/%Y %T") ⏳\033[0m\n\n"

# Default values of arguments
NEW_VERSION=${NEW_VERSION:-}
NUM_APP_SCALE=${NUM_APP_SCALE:-${APP_NUM_SCALE:-}}
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-90}

PHP_CONTAINER_NAME=${PHP_CONTAINER_NAME:-"^/${COMPOSE_PROJECT_NAME}-v(?:[0-9]+)_app_(?:-\d+)?"}

OTHER_ARGUMENTS=()

# @see https://stackoverflow.com/questions/16483119/an-example-of-how-to-use-getopts-in-bash
while true ; do
    case $1 in
        -h|--help)
            usage
            ;;
        -v|--new-version) shift; NEW_VERSION=$1 ;;
        -n|--num-app-scale) shift; NUM_APP_SCALE=$1 ;;
        -d|--app-docker-image) shift; APP_DOCKER_IMAGE=$1 ;;
        --) shift ; break ;;
        *) shift;  OTHER_ARGUMENTS+=("$1") ;;
    esac
    shift
done

# ==============================================================================
# ==============================================================================

readarray -t OLD__PHP_CONTAINERS < <(docker ps --filter name="${PHP_CONTAINER_NAME}" --filter status=running --filter health=healthy --no-trunc --format="{{.Names}}")

NUM_APP_SCALE=${NUM_APP_SCALE:-${#OLD__PHP_CONTAINERS[@]}}

[[ "$NUM_APP_SCALE" -le 0 ]] && NUM_APP_SCALE=2

OLD_VERSION=$(echo ${OLD__PHP_CONTAINERS[0]} | sed -r 's/.*-v([0-9]+)_app_.*/\1/')
NEXT_VERSION=${NEW_VERSION:-"v$(($OLD_VERSION + 1))"}

NEW_PHP_CONTAINER_NAME="^/${COMPOSE_PROJECT_NAME}-${NEXT_VERSION}_app_(?:-\d+)?"

# ==============================================================================
# ==============================================================================

printf "\e[1m# Nova versão dos containers/aplicação no deploy:\e[0m \e[1;3;35m$NEXT_VERSION\e[0m\n"
printf "\e[1m# Quantidade de containers/serviços APP/PHP-Laravel que serão executados:\e[0m \e[1;3;35m$NUM_APP_SCALE\e[0m\n"
printf "\e[1m# Nome da imagem DOCKER da aplicação que será atualizada:\e[0m \e[1;3;35m$APP_DOCKER_IMAGE\e[0m\n"
printf "\e[1;4m# Regex para filtrar e manipular os containers APP/PHP-Laravel:\e[0m \e[46;3;30m$PHP_CONTAINER_NAME\e[0m\n"
printf "\e[1m# Outros argumentos do script:\e[0m \e[1;3;35m${OTHER_ARGUMENTS[*]}\e[0m\n"
echo

echo "### PWD"
echo `pwd`
echo

# ==============================================================================
# ==============================================================================

MAKE_APP="make \
            -f Makefile"

printf "\n\033[3;33m[DEPLOY] Baixando imagem Docker do serviço APP Laravel 🐳 \033[0m\n"

${MAKE_APP} docker/app/pull

printf "\n\033[3;33m[DEPLOY] Executando serviços Docker APP/PHP-Laravel 🐳 - VERSÃO: ${NEXT_VERSION} \033[0m\n"

export CONTAINER_VERSION_SHELL=${NEXT_VERSION}
${MAKE_APP} docker/app/up num_scale=${NUM_APP_SCALE} with_version=true

readarray -t NEW__PHP_CONTAINERS < <(docker ps --filter name="${NEW_PHP_CONTAINER_NAME}" --filter status=running --no-trunc --format="{{.Names}}")

container_state --timeout=$HEALTH_TIMEOUT --containers="${NEW__PHP_CONTAINERS[*]}"

containersInTraefik=''
for containerName in ${NEW__PHP_CONTAINERS[@]}; do
    containersInTraefik="${containersInTraefik}                    - url: http:\/\/${containerName}:8000\n"
done

FILE_TRAEFIK_APP_SERVICE="./traefik/dynamic/app-service.yml"
sed -i -e "/### APP_LOADBALANCER_SERVERS/,/### APP_LOADBALANCER_SERVERS_END/c\### APP_LOADBALANCER_SERVERS\n${containersInTraefik:0:-2}\n### APP_LOADBALANCER_SERVERS_END" $FILE_TRAEFIK_APP_SERVICE

printf "\n\e[42;3;30m[DEPLOY] Serviço Traefik \"app-svc\" atualizado com sucesso com os novos containers APP/Laravel! 🚀 \e[0m\n"

sleep 5s

# curl https://${APP_DOMAIN} >/dev/null 2>&1 || true
# sleep 2s

if [[ ${WITH_NETDATA:-false} == true ]]; then
    FILE_NETDATA_CONF="./netdata/configs/netdata.conf"

    git checkout $FILE_NETDATA_CONF >/dev/null 2>&1 || true

    printf "\n\033[3;33m[DEPLOY] Criando novo container NETDATA para manipular os dados dos novos containers APP 🐳 \033[0m\n\n"

    docker rm --force $(docker ps --quiet --filter name="${NETDATA_CONTAINER_NAME:-$COMPOSE_PROJECT_NAME_(netdata|dockerproxy)}" --filter status=running) >/dev/null 2>&1 || true

    CONTAINERS_TO_EXCLUDE_ON_NETDATA="    enable cgroup ${COMPOSE_PROJECT_NAME}_netdata = no\n    enable cgroup ${COMPOSE_PROJECT_NAME}_dockerproxy = no"

    sed -i \
            -e '/### DISABLE_DOCKER_CONTAINERS$/,/### END_DISABLE_DOCKER_CONTAINERS$/{//!d;}' \
            -e "/### DISABLE_DOCKER_CONTAINERS$/a \\${CONTAINERS_TO_EXCLUDE_ON_NETDATA}" \
        \
        $FILE_NETDATA_CONF

    VIRTUALIZATION=$(systemd-detect-virt -v) make docker/service/up context=netdata
fi

printf "\n\033[3;33m[DEPLOY] Removendo containers da versão antiga(v${OLD_VERSION}) do App/Laravel 🐳 \033[0m\n\n"

set -x
docker rm --force ${OLD__PHP_CONTAINERS[*]} >/dev/null 2>&1 || true
{ set +x; } 2>/dev/null

printf "\n\033[3;33m[DEPLOY] Removendo container parados e volumes não utilizados 🐳 \033[0m\n\n"

set -x
docker container prune --force >/dev/null 2>&1 || true
docker volume prune --force >/dev/null 2>&1 || true
{ set +x; } 2>/dev/null

sed -i \
        -e "/^CONTAINER_VERSION.*/c\CONTAINER_VERSION=${CONTAINER_VERSION_SHELL}" \
        -e "/^APP_NUM_SCALE.*/c\APP_NUM_SCALE=${NUM_APP_SCALE}" \
    \
    .env

docker rm --force $(docker ps --filter name="-v([0-9]+)_(?:queue|scheduler)" --filter status=running -aq) >/dev/null 2>&1 || true
docker volume prune --all --force >/dev/null 2>&1 || true

${MAKE_APP} docker/queue/up with_version=true
${MAKE_APP} docker/scheduler/up with_version=true

printf "\n\033[36m[DEPLOY] Script finalizado com sucesso em $(date +"%d/%m/%Y %T") ⏱\033[0m\n\n"

exit 0
