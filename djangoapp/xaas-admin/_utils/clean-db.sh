#!/usr/bin/env bash


source ".utils-settings.sh"


function printUsage
{
    echo "Usage: $0 <dbName>"
    echo ""
    echo "   <dbName> : Database name to clean"

}

# -----------------------------------------

if [ "$1" == "" ]
then
    printUsage
    exit 1
fi

DB_NAME=$1

# Getting tables list
TABLES=$(mysql --host=${DB_HOST} --port=${DB_PORT} --user=${DB_USER} ${DB_NAME} --password=${DB_PASS} --execute='show tables' | awk '{ print $1}' | grep -v '^Tables' )

for t in $TABLES
do
	echo "Deleting ${t} table from ${DB_NAME} database..."
	mysql --host=${DB_HOST} --port=${DB_PORT} --user=${DB_USER} ${DB_NAME} --password=${DB_PASS} --execute="drop table ${t}"
done
echo "done"

