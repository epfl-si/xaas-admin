#!/bin/bash


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

echo ""
echo "Creating superuser..."

echo "from django.contrib.auth.models import User; User.objects.create_superuser('${username}', '${emailAddress}', 'winterIsComing')" | python manage.py shell



