#!make
# Default values, can be overridden either on the command line of make
# or in .env

check-env:
ifeq ($(wildcard .env),)
	@echo "Please run 'make config' first"
	@exit 1
else
include .env
endif

vars: check-env
	@echo DB-related vars:
	@echo '  MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}'
	@echo '  MYSQL_HOST=${MYSQL_HOST}'
	@echo '  MYSQL_PORT=${MYSQL_PORT}'
	@echo '  MYSQL_DATABASE=${MYSQL_DATABASE}'
	@echo '  MYSQL_USER=${MYSQL_USER}'
	@echo '  MYSQL_PASSWORD=${MYSQL_PASSWORD}'
	@echo ' '
	@echo Django-related vars:
	@echo '  DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY}'

config:
	[ -f .env ] || cp .env.sample .env
	@echo "Please edit .env file to set correct values."
	@echo "When it's done, run 'make build' and then 'make install'"

build: check-env
	@docker-compose build --no-cache
	@docker volume create --name=xaas-mariadb

up: check-env
	@MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
	    MYSQL_HOST=${MYSQL_HOST} \
	    MYSQL_PORT=${MYSQL_PORT} \
	    MYSQL_DATABASE=${MYSQL_DATABASE} \
		MYSQL_USER=${MYSQL_USER} \
		MYSQL_PASSWORD=${MYSQL_PASSWORD} \
		DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY} \
		docker-compose up -d
	@echo "Waiting for containers to start..."
	@sleep 5

up-debug: check-env
	@MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
	    MYSQL_HOST=${MYSQL_HOST} \
	    MYSQL_PORT=${MYSQL_PORT} \
	    MYSQL_DATABASE=${MYSQL_DATABASE} \
		MYSQL_USER=${MYSQL_USER} \
		MYSQL_PASSWORD=${MYSQL_PASSWORD} \
		DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY} \
		docker-compose up

install: up
	@echo "Waiting for entrypoint script..."
	@sleep 8
	@docker exec -it xaas-django bash -l /usr/src/xaas-admin/_utils/create-admin.sh

restart: down up

import-sql: check-env
ifndef SQL_FILE
	$(error Please provide a SQL file as input: SQL_FILE=<file>)
endif
ifeq ($(wildcard ${SQL_FILE}),)
	$(error Given SQL file '${SQL_FILE}' doesn't exists)
	@exit 1
endif
	@echo "Copying file in container..."
	@docker cp ${SQL_FILE} xaas-django:/tmp/dump.sql
	@docker exec -it xaas-django bash -l /usr/src/xaas-admin/_utils/import-sql.sh /tmp/dump.sql


exec-django: check-env
	@docker exec -it xaas-django bash -l

exec-mariadb: check-env
	@docker exec -it xaas-mariadb bash -l

down: check-env
	@docker-compose down

clean: down
	@-docker image rm xaas-django

clean-all: clean
	@docker volume rm xaas-mariadb
