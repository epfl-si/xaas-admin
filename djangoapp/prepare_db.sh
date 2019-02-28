#!/bin/bash
python manage.py makemigrations
python manage.py migrate

echo ""
echo "==================================================="
echo "==             DJANGO : XAAS-ADMIN               =="
echo "==================================================="

echo ""
echo "We now have to create one superuser on Django"
echo "---------------------------------------------"
echo ""
echo -n "Please enter a gaspar username: "
read username
echo -n "Please enter an email address: "
read emailAddress
echo -n "Please enter a dummy password: "
read -s dummyPassword

echo ""
echo "Creating superuser..."

echo "from django.contrib.auth.models import User; User.objects.create_superuser('${username}', '${emailAddress}', '${dummyPassword}')" | python manage.py shell



