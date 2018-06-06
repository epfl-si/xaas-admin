#!/usr/bin/env bash


SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SECRETS_FILE="${SCRIPT_PATH}/../../secrets.json"
DB_USER="xaas_admin_user"


function printUsage
{
    echo "Usage: $0 <dbName>"
    echo ""
    echo "   <dbName> : Database name to clean"

}

function extractSecretValue
{
    secretKey=$1

    cat ${SECRETS_FILE} | grep ${secretKey} | awk '{print $2}' | awk -F\" '{print $2}'

}

# -----------------------------------------

if [ "$1" == "" ]
then
    printUsage
    exit 1
fi

# Extracting DB Password from file
dbPass=`extractSecretValue "DB_USER_PWD"`
dbPort=`extractSecretValue "DB_PORT"`
dbHost=`extractSecretValue "DB_HOST"`

if [ "${dbHost}" == "" ]
then
    dbHost="localhost"
fi

# Getting tables list
TABLES=$(mysql --host=${dbHost} --port=${dbPort} --user=${DB_USER} $1 --password=${dbPass} --execute='show tables' | awk '{ print $1}' | grep -v '^Tables' )

for t in $TABLES
do
	echo "Deleting $t table from $1 database..."
	mysql --host=${dbHost} --port=${dbPort} --user=${DB_USER} $1 --password=${dbPass} --execute="drop table $t"
done
echo "done"

