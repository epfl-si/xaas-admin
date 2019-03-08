#!/bin/bash

echo "Waiting for MariaDB..."

while ! mysql --protocol TCP -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "show databases;" > /dev/null 2>&1; do
    sleep 2
    echo "Waiting for MariaDB..."
done
echo "Oh! hello MariaDB! It's nice to see you!"


python manage.py makemigrations
python manage.py migrate

# Starting Django
echo "Django up and running!"
python manage.py runserver "0.0.0.0:80"

