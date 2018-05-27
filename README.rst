================================
xaas-admin
================================

.. image:: https://travis-ci.com/epfl-idevelop/xaas-admin.svg?token=m9yDqN9WioRf8qE8m6gt&branch=master
    :target: https://travis-ci.com/epfl-idevelop/xaas-admin

.. image:: https://img.shields.io/badge/code%20style-pep8-orange.svg
    :target: https://www.python.org/dev/peps/pep-0008/

.. image:: https://img.shields.io/badge/python-3.5.4-blue.svg
    :target: https://www.python.org/downloads/release/python-354/


General description of the application
======================================
This application ...

Version
-------
python 3.5.4
django 1.11 LTS

How install
===========

Clone the git repository
---------------------------
git clone git@github.com:epfl-idevelop/xaas-admin.git
cd xaas-admin

Create a virtualenv
----------------------
You may install pyenv https://github.com/pyenv/pyenv
pyenv virtualenv 3.5.4 xaas-admin

Activate a virtualenv
------------------------
pyenv activate xaas-admin

Install python packages
--------------------------
pip install -r requirements/local.txt

Create a symlink
----------------
ln -s local.py src/config/settings/default.py

Create MySQL DB and MySQL user
------------------------------
You must create a MySQL DB 'xaas-admin'
You must create a MySQL user 'xaas-admin' with all privileges on xaas-admin DB
The database information is in the local.txt and secrets.json files

Build migrations
-------------------
python src/manage.py makemigrations

Build all tables, index, etc
----------------------------
python src/manage.py migrate

Create a super user
-------------------
python src/manage.py createsuperuser --username=charmier --email=gregory.charmier@epfl.ch --settings=config.settings.local

--username must be a gaspar username

Run server
-----------
python src/manage.py runserver

Go to this URL
---------------
http://127.0.0.1:8000/


Django commands
===============

How delete a user
-----------------
python src/manage.py shell --settings=config.settings.local
Python 3.5.4 (default, Sep 16 2017, 06:56:51)
[GCC 5.4.0 20160609] on linux
Type "help", "copyright", "credits" or "license" for more information.
(InteractiveConsole)
>>> from django.contrib.auth.models import User
>>> User.objects.get(username="charmier").delete()
(1, {'auth.User_groups': 0, 'admin.LogEntry': 0, 'auth.User_user_permissions': 0, 'auth.User': 1})


Test server
===========

Create the database
-------------------
kis@exopgesrv34:/var/www/vhosts/xaas-admin.epfl.ch/private/virtenv$ source /opt/rh/rh-python35/enable
kis@exopgesrv34:/var/www/vhosts/xaas-admin.epfl.ch/private/virtenv$ source xaas-admin-env/bin/activate
(xaas-admin-env)kis@exopgesrv34:/var/www/vhosts/xaas-admin.epfl.ch/private/virtenv$ cd ..
(xaas-admin-env)kis@exopgesrv34:/var/www/vhosts/xaas-admin.epfl.ch/private$ ll
total 12
drwxrwsr-x. 2 kis  kis 4096 16 mai 14:02 requirements
drwxrwsr-x. 4 kis  kis 4096 16 mai 14:02 src
dr-xrwsr-x. 3 root kis 4096 10 mai 07:36 virtenv
(xaas-admin-env)kis@exopgesrv34:/var/www/vhosts/xaas-admin.epfl.ch/private$ python src/manage.py migrate --settings=config.settings.test


Best pratices
=============

PEP8 convention
---------------
flake8 --exclude=migrations --max-line-length=120

Run tests
---------
coverage run src/manage.py test --settings=config.settings.local

Generate HTML report
--------------------
coverage html

Open with your web browser the file htmlcov/index.html
