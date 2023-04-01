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

root_path := $(shell dirname -- `pwd`)
docker_folder := $(if $(docker_folder),$(docker_folder),./docker)

uname_OS := $(shell uname -s)
user_UID := $(shell id -u)
user_GID := $(shell id -g)
current_uid ?= "${user_UID}:${user_GID}"

ifeq ($(uname_OS),Darwin)
	user_UID := 1001
	user_GID := 1001
endif

# Handling environment variables
app_local_folder := $(if $(APP_LOCAL_FOLDER_SHELL),$(APP_LOCAL_FOLDER_SHELL),$(ROOT_PATH)/$(APP_LOCAL_FOLDER))

# Passing the >_ options option
options := $(if $(options),$(options),--env-file $(docker_folder)/.env)
# Passing the >_ up_options option
up_options := $(if $(up_options),$(up_options),--force-recreate --no-build --no-deps --detach)

# Passing the >_ project_name option
project_name := $(if $(project_name),$(project_name),$(COMPOSE_PROJECT_NAME))
version := $(if $(version),$(version),$(if $(CONTAINER_VERSION_SHELL),$(CONTAINER_VERSION_SHELL),$(CONTAINER_VERSION)))

# Passing the >_ common_options option
common_options := $(if $(common_options),$(common_options),--compatibility --ansi=auto --project-name $(project_name)-$(version))

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
	@sed -i "/LOCAL_DOCKER_FOLDER=.*/c\LOCAL_DOCKER_FOLDER=${docker_folder}" .env
	@sed -i "/^# ROOT_PATH/c\ROOT_PATH=$(root_path)" .env
	@sed -i "/# USER_UID=.*/c\USER_UID=$(user_UID)" .env
	@sed -i "/# USER_GID=.*/c\USER_GID=$(user_GID)" .env
	@sed -i "/^# CURRENT_UID/c\CURRENT_UID=${current_uid}" .env
	@echo
	@echo $(call message_success, Run \`make docker/config-env\` successfully executed)

# make php/composer-install
.PHONY: php/composer-install
php/composer-install:
	@echo
	@echo $(call message_info, Installing PHP dependencies with Composer 🗂)
	@echo
	docker run \
		--rm \
		--tty \
		--interactive \
		--volume $(app_local_folder):/app \
		--workdir /app \
		$(if $(options), $(options),) \
		composer:2.0 \
			install \
				--optimize-autoloader \
				--ignore-platform-reqs \
				--prefer-dist \
				--ansi \
				--no-dev \
				--no-interaction

.PHONY: docker/healthcheck
docker/healthcheck:
	@timeout=60; counter=0; \
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
	@echo $(call message_success, HEALTHCHECK do Container \"$${container}\" OK)

.PHONY: docker/app/build
docker/app/build:
	@echo
	@echo $(call message_info, Build an image APP... 🏗)
	@echo
	docker compose \
		-f $(docker_folder)/php/services/app/docker-compose.yml \
		--ansi=auto \
		--env-file $(docker_folder)/.env \
		build --progress=plain app

.PHONY: docker/app/pull
docker/app/pull:
	@echo
	@echo $(call message_info, Pull an image APP... 🏗)
	@echo
	docker compose \
		-f $(docker_folder)/php/services/app/docker-compose.yml \
		--ansi=auto \
		--env-file $(docker_folder)/.env \
		pull app

.PHONY: docker/app/up
docker/app/up:
# make -f docker/Makefile docker/app/up
	@echo
	@echo $(call message_info, Running APP Container... 🚀)
	@echo
	$(MAKE) -f $(docker_folder)/Makefile \
			--no-print-directory \
			docker/service/up \
			context="php/services/app" \
			scale=$(if $(num_scale),$(num_scale),$(if $(APP_DOCKER_SCALE),$(APP_DOCKER_SCALE),1)) \
			service=$(if $(scale_service),$(scale_service),app) \
			version=$(if $(new_version),$(new_version),$(version))

.PHONY: docker/minio/up
docker/minio/up:
# make -f docker/Makefile docker/minio/up
	@echo
	@echo $(call message_info, Running MinIO Container... 🗄)
	@echo
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/service/up context="minio"

.PHONY: docker/queue/up
docker/queue/up:
# make -f docker/Makefile docker/queue/up
	@echo
	@echo $(call message_info, Running QUEUE Container... 🚀)
	@echo
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/service/up context="php/services/queue"

.PHONY: docker/scheduler/up
docker/scheduler/up:
# make -f docker/Makefile docker/scheduler/up
	@echo
	@echo $(call message_info, Running SCHEDULER Container... 🚀)
	@echo
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/service/up context="php/services/scheduler"

.PHONY: docker/database/up
docker/database/up:
	@echo
	@echo $(call message_info, Running Docker Database... 🚀)
	@echo
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/service/up context=mysql up_options="--force-recreate --detach"

.PHONY: docker/redis/up
docker/redis/up:
	@echo
	@echo $(call message_info, Running Docker Redis... 🚀)
	@echo
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/service/up context=redis up_options="--force-recreate --detach"

# make  docker/service/up \
		context=FOLDER_IN_SERVICES \
		options=--verbose \
		up_options="--force-recreate" \
		services="services_in_docker_compose"
.PHONY: docker/service/up
docker/service/up:
	@docker compose -f $(docker_folder)/$(context)/docker-compose.yml \
		$(options) $(common_options) \
		up $(up_options) \
		$(if $(and $(scale), $(service)),--scale $(service)=$(scale)) $(if $(services),$(services),)

.PHONY: docker/up
docker/up:
# make -f docker/Makefile docker/up database_container="app_database" redis_container="app_redis"
	@echo
	@echo $(call message_info, Running Docker Application... 🚀)
	@echo
	@docker compose -f $(docker_folder)/docker-compose.yml up
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/database/up
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/healthcheck container=$(if $(database_container),$(database_container),app_database)
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/redis/up
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/healthcheck container=$(if $(redis_container),$(redis_container),app_redis)
	@$(MAKE) -f $(docker_folder)/Makefile --no-print-directory docker/app/up
