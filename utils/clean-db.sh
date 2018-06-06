#!/usr/bin/env bash


SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SECRETS_FILE="${SCRIPT_PATH}/../secrets.json"
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


request="SET FOREIGN_KEY_CHECKS = 0;
SET @tables = NULL;
SELECT GROUP_CONCAT(table_schema, '.', table_name) INTO @tables
  FROM information_schema.tables
  WHERE table_schema = '$1';

  SET @tables = CONCAT('DROP TABLE ', @tables);
PREPARE stmt FROM @tables;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
SET FOREIGN_KEY_CHECKS = 1;"

echo "Deleting tables in '$1' database..."
mysql --host=${dbHost} --port=${dbPort} --user=${DB_USER} $1 --password=${dbPass} --execute="${request}"

echo "done"

