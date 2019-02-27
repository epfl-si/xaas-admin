#!/bin/bash

#docker run -d                             \
#           --name xaas-mariadb            \
#           -e MYSQL_ROOT_PASSWORD=root    \
#           -e MYSQL_USER=django           \
#           -e MYSQL_PASSWORD=django       \
#           -e MYSQL_DATABASE=django       \
#           -v xaas-mariadb:/var/lib/mysql      \
#           mariadb
#
#sleep 10
#
#docker run -it                            \
#           --name xaas-django             \
#           xaas/django bash
#

docker exec -it  \
	  xaas-django bash -l