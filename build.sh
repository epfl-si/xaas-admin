#!/bin/bash

docker-compose build --no-cache
#docker build -t xaas/django djangoapp/. --no-cache
#
#
#docker build -t xaas/nginx nginx/. --no-cache

docker volume create --name=xaas-mariadb
#docker network create epfl-xaas