#!/usr/bin/env bash

SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SECRETS_FILE="${SCRIPT_PATH}/../../secrets.json"

function extractSecretValue
{
    secretKey=$1

    cat ${SECRETS_FILE} | grep ${secretKey} | awk '{print $2}' | awk -F\" '{print $2}'

}

DB_USER="xaas_admin_user"

# Extracting DB Password from file
DB_PASS=`extractSecretValue "DB_USER_PWD"`
DB_PORT=`extractSecretValue "DB_PORT"`
DB_HOST=`extractSecretValue "DB_HOST"`

if [ "${DB_HOST}" == "" ]
then
    DB_HOST="localhost"
fi

