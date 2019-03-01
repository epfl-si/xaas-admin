#!/bin/bash



echo -n "Importing... "
mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} -h ${MYSQL_HOST} ${MYSQL_DATABASE} < $1
echo "done"

rm $1