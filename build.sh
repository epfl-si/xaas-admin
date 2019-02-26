#!/bin/bash

docker build -t xaas/django djangoapp/. --no-cache

docker build -t xaas/nginx nginx/. --no-cache

docker network create epfl-xaas