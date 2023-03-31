# Sets the default goal to be used if no targets were specified on the command line
.DEFAULT_GOAL := help

ifneq ("$(wildcard .env)","")
include .env
export
endif

ifneq ("$(wildcard scripts/envs/deploy.env)","")
include scripts/envs/deploy.env
export
endif

docker_path := $(shell realpath $(DOCKER_PATH))

uname_OS := $(shell uname -s)
user_UID := $(if $(USER_UID_SHELL),$(USER_UID_SHELL),$(shell id -u))
user_GID := $(if $(USER_GID_SHELL),$(USER_GID_SHELL),$(shell id -g))
current_uid ?= "${user_UID}:${user_GID}"

ifeq ($(uname_OS),Darwin)
	user_UID := 1001
	user_GID := 1001
endif

# Handling environment variables
app_full_path := $(if $(APP_PATH_SHELL),$(APP_PATH_SHELL),$(APP_PATH))

# Passing the >_ options option
options := $(if $(options),$(options),--env-file $(docker_path)/.env)
# Passing the >_ up_options option
up_options := $(if $(up_options),$(up_options),--force-recreate --no-build --no-deps --detach)

# Passing the >_ project_name option
project_name := $(if $(project_name),$(project_name),$(COMPOSE_PROJECT_NAME))
version := $(if $(version),$(version),$(if $(CONTAINER_VERSION_SHELL),$(CONTAINER_VERSION_SHELL),$(CONTAINER_VERSION)))

project_name_and_version := $(if $(with_version),$(project_name)-$(version),$(project_name))

# Passing the >_ common_options option
common_options := $(if $(common_options),$(common_options),--compatibility --ansi=auto --project-name $(project_name_and_version))

# ==================================================================================== #
# HELPERS
# ==================================================================================== #

# internal functions
define message_failure
	"\033[1;31m ❌$(1)\033[0m"
endef

define message_success
	"\033[1;32m ✅$(1)\033[0m"
endef

define message_info
	"\033[0;34m❕$(1)\033[0m"
endef

# ==================================================================================== #
# DOCKER
# ==================================================================================== #

.PHONY: docker/config-env
docker/config-env:
	@cp -n .env.compose .env || true
	@sed -i "/^# PWD/c\PWD=$(shell pwd)" .env
	@sed -i "/^# APP_PATH/c\APP_PATH=$(shell dirname -- `pwd`)" .env
	@sed -i "/# USER_UID=.*/c\USER_UID=$(user_UID)" .env
	@sed -i "/# USER_GID=.*/c\USER_GID=$(user_GID)" .env
	@sed -i "/^# CURRENT_UID/c\CURRENT_UID=${current_uid}" .env
	@cp ./grafana/.env.container ./grafana/.env
	@cp ./mongodb/.env.container ./mongodb/.env
	@cp ./mysql/.env.container ./mysql/.env
	@cp ./php/services/app/.env.container ./php/services/app/.env
	@cp ./php/services/queue/.env.container ./php/services/queue/.env
	@cp ./php/services/scheduler/.env.container ./php/services/scheduler/.env
	@cp ./soketi/.env.container ./soketi/.env
	@echo
	@echo -e $(call message_success, Run \`make docker/config-env\` successfully executed)

# make php/composer-install
.PHONY: php/composer-install
php/composer-install:
	@echo
	@echo -e $(call message_info, Installing PHP dependencies with Composer 🗂)
	@echo
	docker run \
		--rm \
		--tty \
		--interactive \
		--volume $(app_full_path):/app \
		--workdir /app \
		$(if $(options), $(options),) \
		composer:2.5 \
			install \
				--optimize-autoloader \
				--ignore-platform-reqs \
				--prefer-dist \
				--ansi \
				--no-dev \
				--no-interaction

.PHONY: docker/healthcheck
docker/healthcheck: $(eval SHELL:=/bin/bash)
	@timeout=90; counter=0; \
	printf "\n\033[3;33mEsperando healthcheck do container de \"$${container}\" = \"healthy\" ⏳ \033[0m\n" ; \
	until [[ "$$(docker container inspect -f '{{.State.Health.Status}}' $${container})" == "healthy" ]] ; do \
		printf '.' ; \
		if [[ $${timeout} -lt $${counter} ]]; then \
			printf "\n\033[1;31mERROR: Timed out waiting for \"$${container}\" to come up/healthy ❌\033[0m\n\n" ; \
			exit 1 ; \
		fi ; \
		\
		printf "\n\033[35mWaiting for \"$${container}\" to be ready/healthy ($${counter}/$${timeout}) ⏱ \033[0m\n" ; \
		sleep 5s; counter=$$((counter + 5)) ; \
	done
	@echo
	@echo -e $(call message_success, HEALTHCHECK do Container \"$${container}\" OK)
.PHONY: docker/app/pull
docker/app/pull:
	@echo
	@echo -e $(call message_info, Pull an image APP... 🏗)
	@echo
	docker pull ${APP_DOCKER_IMAGE}
# docker compose \
	# -f $(docker_path)/php/services/app/docker-compose.yml \
	# --ansi=auto \
	# --env-file $(docker_path)/.env \
	# pull app

# .PHONY: docker/app/build
# docker/app/build:
# 	@echo
# 	@echo -e $(call message_info, Build an image APP... 🏗)
# 	@echo
# 	docker compose \
# 		-f $(docker_path)/php/services/app/docker-compose.yml \
# 		--ansi=auto \
# 		--env-file $(docker_path)/.env \
# 		build --progress=plain app

.PHONY: docker/app/build
docker/app/build:
	@echo
	@echo -e $(call message_info, Build an image APP... 🏗)
	@echo
	DOCKER_BUILDKIT=1 docker build \
		--progress=plain \
		--target main \
		--cache-from ${APP_DOCKER_REPO}:vendor \
		--cache-from ${APP_DOCKER_REPO}:frontend \
		--cache-from ${APP_DOCKER_REPO}:dependencies \
		--cache-from ${APP_DOCKER_IMAGE} \
		--tag ${APP_DOCKER_IMAGE} \
		--file ${DOCKER_PHP_PATH}/Dockerfile \
		--build-arg USER_UID=${USER_UID} \
		--build-arg USER_GID=${USER_GID} \
		--build-arg DOCKER_FOLDER=${DOCKER_FOLDER} \
		--build-arg APP_DOCKER_REPO=${APP_DOCKER_REPO} \
	${APP_PATH}

.PHONY: docker/app/push
docker/app/push:
	@echo
	@echo -e $(call message_info, Push Docker Image [BLOG] 🐳)
	@echo
	docker push ${APP_DOCKER_IMAGE}

.PHONY: docker/app/dependencies/pull
docker/app/dependencies/pull:
	@echo
	@echo -e $(call message_info, Pull 🚚 Docker Image [DEPENDENCIES] 🐳)
	@echo
	docker pull ${APP_DOCKER_REPO}:dependencies

.PHONY: docker/app/dependencies/build
docker/app/dependencies/build: $(eval SHELL:=/bin/bash)
	@echo
	@echo -e $(call message_info, Creating the [DEPENDENCIES] image of the application 🏗)
	@echo
	@CACHE_FROM="--cache-from ${APP_DOCKER_REPO}:dependencies"; \
	if [ "$${no_cache_from:-false}" = "true" ]; then \
		CACHE_FROM="" ; \
	fi ; \
	DOCKER_BUILDKIT=1 docker build \
		--progress=plain \
		--target dependencies \
		--cache-from ${APP_DOCKER_REPO}:vendor \
		$$CACHE_FROM \
		--tag ${APP_DOCKER_REPO}:dependencies \
		--file ${DOCKER_PHP_PATH}/Dockerfile \
	${APP_PATH}

.PHONY: docker/app/dependencies/push
docker/app/dependencies/push:
	@echo
	@echo -e $(call message_info, Push 📦 an image [DEPENDENCIES] 🐳)
	@echo
	docker push ${APP_DOCKER_REPO}:dependencies

.PHONY: docker/app/vendor/pull
docker/app/vendor/pull:
	@echo
	@echo -e $(call message_info, Pull 🚚 Docker Image [VENDOR] 🐳)
	@echo
	docker pull ${APP_DOCKER_REPO}:vendor

.PHONY: docker/app/vendor/build
docker/app/vendor/build: $(eval SHELL:=/bin/bash)
	@echo
	@echo -e $(call message_info, Creating the [VENDOR] image of the application 🏗)
	@echo
	@CACHE_FROM="--cache-from ${APP_DOCKER_REPO}:vendor"; \
	if [ "$${no_cache_from:-false}" = "true" ]; then \
		CACHE_FROM="" ; \
	fi ; \
	DOCKER_BUILDKIT=1 docker build \
		--progress=plain \
		--target vendor \
		$$CACHE_FROM \
		--tag ${APP_DOCKER_REPO}:vendor \
		--file ${DOCKER_PHP_PATH}/Dockerfile \
	${APP_PATH}

.PHONY: docker/app/vendor/push
docker/app/vendor/push:
	@echo
	@echo -e $(call message_info, Push 📦 an image [VENDOR] 🐳)
	@echo
	docker push ${APP_DOCKER_REPO}:vendor

.PHONY: docker/app/frontend/pull
docker/app/frontend/pull:
	@echo
	@echo -e $(call message_info, Pull 🚚 Docker Image [FRONTEND] 🐳)
	@echo
	docker pull ${APP_DOCKER_REPO}:frontend

.PHONY: docker/app/frontend/build
docker/app/frontend/build: $(eval SHELL:=/bin/bash)
	@echo
	@echo -e $(call message_info, Creating the [FRONT-END] image of the application 🏗)
	@echo
	@CACHE_FROM="--cache-from ${APP_DOCKER_REPO}:frontend"; \
	if [ "$${no_cache_from:-false}" = "true" ]; then \
		CACHE_FROM="" ; \
	fi ; \
	DOCKER_BUILDKIT=1 docker build \
		--progress=plain \
		--target frontend \
		$$CACHE_FROM \
		--tag ${APP_DOCKER_REPO}:frontend \
		--file ${DOCKER_PHP_PATH}/Dockerfile \
	${APP_PATH}

.PHONY: docker/app/frontend/push
docker/app/frontend/push:
	@echo
	@echo -e $(call message_info, Push 📦 an image [FRONTEND] 🐳)
	@echo
	docker push ${APP_DOCKER_REPO}:frontend

.PHONY: docker/app/up
docker/app/up:
	@echo
	@echo -e $(call message_info, Running APP Container... 🚀)
	@echo
	$(MAKE) -f $(docker_path)/Makefile \
			--no-print-directory \
			docker/service/up \
			context="php/services/app" \
			scale=$(if $(num_scale),$(num_scale),$(if $(APP_NUM_SCALE),$(APP_NUM_SCALE),1)) \
			service=$(if $(scale_service),$(scale_service),app) \
			with_version=true \
			version=$(if $(new_version),$(new_version),$(version))

.PHONY: docker/queue/up
docker/queue/up:
	@echo
	@echo -e $(call message_info, Running QUEUE Container... 🚀)
	@echo
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/service/up context="php/services/queue"

.PHONY: docker/scheduler/up
docker/scheduler/up:
	@echo
	@echo -e $(call message_info, Running SCHEDULER Container... 🚀)
	@echo
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/service/up context="php/services/scheduler"

.PHONY: docker/database/up
docker/database/up:
	@echo
	@echo -e $(call message_info, Running Docker Database... 🚀)
	@echo
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/service/up context=mysql up_options="--force-recreate --detach"

.PHONY: docker/redis/up
docker/redis/up:
	@echo
	@echo -e $(call message_info, Running Docker Redis... 🚀)
	@echo
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/service/up context=redis up_options="--force-recreate --detach"

.PHONY: docker/traefik/up
docker/traefik/up:
	@echo
	@echo -e $(call message_info, Running Traefik Container... 🚀)
	@echo
	@$(MAKE) -f $(docker_path)/Makefile \
			--no-print-directory \
			docker/service/up \
			context="traefik" \
			services="traefik"

# make  docker/service/up \
		context=FOLDER_IN_SERVICES \
		options=--verbose \
		up_options="--force-recreate" \
		services="services_in_docker_compose"
.PHONY: docker/service/up
docker/service/up:
	@docker compose -f $(docker_path)/$(context)/docker-compose.yml \
		$(options) $(common_options) \
		up $(up_options) \
		$(if $(and $(scale), $(service)),--scale $(service)=$(scale)) $(if $(services),$(services),)

.PHONY: docker/up
docker/up:
# make -f docker/Makefile docker/up database_container="app_database" redis_container="app_redis"
	@echo
	@echo -e $(call message_info, Running Docker Application... 🚀)
	@echo
	@docker compose -f $(docker_path)/docker-compose.yml up
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/database/up
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/healthcheck container=$(if $(database_container),$(database_container),app_database)
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/redis/up
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/healthcheck container=$(if $(redis_container),$(redis_container),app_redis)
	@$(MAKE) -f $(docker_path)/Makefile --no-print-directory docker/app/up
