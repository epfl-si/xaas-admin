#!/bin/bash

docker stop xaas-django
docker stop xaas-nginx
docker stop xaas-mariadb

docker rm xaas-django
docker rm xaas-nginx
docker rm xaas-mariadb