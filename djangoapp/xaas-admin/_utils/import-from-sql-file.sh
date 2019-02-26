#!/usr/bin/env bash

source ".utils-settings.sh"



function printUsage
{
    echo "Usage: $0 <DBName> <SQLFile>"
    echo ""
    echo "   <dbName>  : Database name in which to import data"
    echo "   <SQLFile> : SQL File to import"

}

# -----------------------------------------

if [ $# -lt 2 ]
then
    printUsage
    exit 1
fi


# Saving parameters
DB_NAME=$1
SQL_FILE=$2


if [ ! -e ${SQL_FILE} ]
then
    echo "File '${SQL_FILE}' doesn't exists!"
    exit 1
fi

echo "Importing from file..."
mysql --host=${DB_HOST} --port=${DB_PORT} --user=${DB_USER} ${DB_NAME} --password=${DB_PASS} < ${SQL_FILE}
echo "Import done"