#!/bin/bash

docker run -d                             \
           --name xaas-mariadb            \
           -e MYSQL_ROOT_PASSWORD=root    \
           -e MYSQL_USER=django           \
           -e MYSQL_PASSWORD=django       \
           -e MYSQL_DATABASE=django       \
           -v mariadb:/var/lib/mysql      \
           --net=epfl-xaas                \
           mariadb

sleep 5

docker run -d                             \
           --name xaas-django             \
           --net=epfl-xaas                \
           xaas/django

docker run -d                             \
           --name xaas-nginx              \
           --net=epfl-xaas                \
           -p 127.0.0.1:8888:80           \
           xaas/nginx