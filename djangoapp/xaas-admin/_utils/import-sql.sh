#!/bin/bash

# Check parameter
if [ "$1" == "" ]
then
    echo "Usage: $0 <pathToSQLFile>"
    exit 1
fi

# Check if given file exists
if [ ! -e $1 ]
then
    echo "Error! given file ($1) doesn't exists!"
    exit 1
fi

echo -n "Importing... "
mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} -h ${MYSQL_HOST} ${MYSQL_DATABASE} --port=${MYSQL_PORT} < $1
echo "done"

echo ""
echo "Don't forget to remove '$1' file"