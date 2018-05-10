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
python 3.5.4 ? to check with the prod environment
django 2.0

How install
===========

pyenv https://github.com/pyenv/pyenv

To create a virtualenv
----------------------
pyenv virtualenv 3.5.4 xaas-admin

To activate a virtualenv
------------------------
pyenv activate xaas-admin

To install python packages
--------------------------
pip install -r requirements/local.txt

Create a symlink
----------------
ln -s local.py default.py


Django commands
===============

How run application
-------------------

python src/manage.py runserver --settings=config.settings.local

How build DB
------------
python src/manage.py migrate --settings=config.settings.local

How build migration
-------------------
python src/manage.py makemigrations --settings=config.settings.local

How create a super user
-----------------------
python src/manage.py createsuperuser --username=charmier --email=gregory.charmier@epfl.ch --settings=config.settings.local

--username must be a gaspar username

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


Best pratices
=============

PEP8 convention
---------------
flake8 --exclude=migrations --max-line-length=120
