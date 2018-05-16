"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""

from .base import *  # noqa

DEBUG = True

ALLOWED_HOSTS = [
    'xaas-admin-test.epfl.ch',
]

# Database
# https://docs.djangoproject.com/en/2.0/ref/settings/#databases

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'HOST': 'mysql-scx-p1',
        'NAME': 'rdp',
        'USER': 'xaas_admin_user',
        'PASSWORD': 'zjKbPLySbQfA',
        'PORT': '33001',
    }
}

DEBUG_TOOLBAR_CONFIG = {
    'SHOW_TOOLBAR_CALLBACK': 'config.settings.local.custom_show_toolbar',
}

SERVER_NAME = "test"

STATIC_ROOT = '/var/www/vhosts/xaas-admin.epfl.ch/htdocs/'
