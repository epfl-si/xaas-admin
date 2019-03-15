#!/bin/bash

# Checking prerequisites
if [ "${DJANGO_SETTINGS_MODULE}" == "" ]
then
    echo "Error! Building arg 'DJANGO_SETTINGS_MODULE' empty!"
    exit 1
fi

#### Pip install ####
reqFile=`echo ${DJANGO_SETTINGS_MODULE} | awk -F. '{print $3".txt"}'`

echo "Updating modules using pip (${reqFile})... "

pip install --no-cache-dir -r /tmp/${reqFile}



#### Application source ####
TMP_APP_SOURCE_FILES=/tmp/xaas-admin
WITNESS_FILE=/tmp/source-done

# If this is first execution of container,
if [ ! -e ${WITNESS_FILE} ]
then
    # We set correct location for app source files
    echo "Setting correct source for Django app..."

    # If we have to use external source files for app (development purpose),
    if [ "${DJANGO_SETTINGS_MODULE}" = "config.settings.local" ]
    then
        echo "-> Using external source for app, deleting what was copied..."
        rm -rf ${TMP_APP_SOURCE_FILES}

    else # We have to use internal source (Test or production, typically on OpenShift)

        echo "-> Using internal source for app, copying to correct place..."
        mv ${TMP_APP_SOURCE_FILES} /usr/src/

    fi

    # We add the witness file right after. In fact there's an error on OpenShift (permission denied) if
    # we try to just move source files from one location to another... so we use witness file.
    touch ${WITNESS_FILE}

fi