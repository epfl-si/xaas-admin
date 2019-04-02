"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""

from .base import *  # noqa

DEBUG = True

ALLOWED_HOSTS = [
    '127.0.0.1',
    'localhost',
]

# Database
# https://docs.djangoproject.com/en/2.0/ref/settings/#databases
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'HOST': get_mandatory_env('MYSQL_HOST'),  # noqa
        'NAME': get_mandatory_env('MYSQL_DATABASE'),
        'USER': get_mandatory_env('MYSQL_USER'),
        'PASSWORD': get_mandatory_env('MYSQL_PASSWORD'),  # noqa
        'PORT': get_mandatory_env('MYSQL_PORT'),  # noqa
    }
}

DEBUG_TOOLBAR_CONFIG = {
    'SHOW_TOOLBAR_CALLBACK': 'config.settings.local.custom_show_toolbar',
}

SERVER_NAME = "local"

STATIC_ROOT = '/usr/src/xaas-admin/static/'
#STATIC_URL = 'https://raw.githubusercontent.com/django/django/master/django/contrib/admin/static/'