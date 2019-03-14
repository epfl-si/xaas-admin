#!/bin/bash

TMP_APP_SOURCE_FILES=/tmp/app-src/xaas-admin

# If this is first execution of container,
if [ -e ${TMP_APP_SOURCE_FILES} ]
then
    # We set correct location for app source files
    echo "Setting correct source for Django app..."

    # If we have to use external source files for app (development purpose),
    if [ "${DJANGO_SETTINGS_MODULE}" = "config.settings.local" ]
    then
        echo "-> Using external source for app, deleting what was copied..."
        rm -rf ${TMP_APP_SOURCE_FILES}

    else # We have to use internal source (Test or production, typically on OpenShift)

        echo "-> Using internal source for app, moving to correct place..."
        mv -f ${TMP_APP_SOURCE_FILES} /usr/src/
    fi

fi



echo "Waiting for MariaDB..."

# We try to connect to database and if unsuccessful, we try again a few seconds later...
# Note: MySQL host is automatically taken from env var.
while ! mysql --protocol TCP -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -P"${MYSQL_PORT}" -e "show databases;" > /dev/null 2>&1; do
    sleep 3
    echo "Waiting for MariaDB..."
done
echo "Oh! hello MariaDB! It's nice to see you!"

# Django "updates" in Database
python manage.py makemigrations
python manage.py migrate

# Starting Django
echo "Django up and running!"
python manage.py runserver "0.0.0.0:80"

