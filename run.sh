#!/bin/bash

docker-compose up

#docker run -d                             \
#           --name xaas-mariadb            \
#           -e MYSQL_ROOT_PASSWORD=root    \
#           -e MYSQL_USER=django           \
#           -e MYSQL_PASSWORD=django       \
#           -e MYSQL_DATABASE=django       \
#           -v mariadb:/var/lib/mysql      \
#           mariadb
#
#sleep 5
#
#docker run -d                             \
#           --name xaas-django             \
#           xaas/django
#
#sleep 5
#
#docker run -d                             \
#           --name xaas-nginx              \
#           -p 127.0.0.1:8888:80           \
#           xaas/nginx