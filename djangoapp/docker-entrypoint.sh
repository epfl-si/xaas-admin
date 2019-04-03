#!/bin/bash



echo "Waiting for MariaDB..."

# We try to connect to database and if unsuccessful, we try again a few seconds later...
# Note: MySQL host is automatically taken from env var.
while ! mysql --protocol TCP -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -P"${MYSQL_PORT}" -e "show databases;" > /dev/null 2>&1; do
    sleep 3
    echo "Waiting for MariaDB..."
done
echo "Oh! hello MariaDB! It's nice to see you!"

# If we're on production, we have to copy static files
if [ "${DJANGO_SETTINGS_MODULE}" = "config.settings.prod" ]
then
    echo "Copying static files..."
    python manage.py collectstatic --noinput
fi

echo "Updating database..."
# Django "updates" in Database
python manage.py makemigrations
python manage.py migrate

# Starting Django
echo "Starting Django..."
python manage.py runserver "0.0.0.0:8080"

