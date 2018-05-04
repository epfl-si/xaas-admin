================================
xaas-admin
================================

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

Best pratices
=============

PEP8 convention
---------------
flake8 --exclude=migrations --max-line-length=120
