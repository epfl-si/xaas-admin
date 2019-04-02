"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""

from .base import *  # noqa

DEBUG = False

ALLOWED_HOSTS = [
    'xaas-admin.epfl.ch',
    'xaas-admin-test.epfl.ch',
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

SERVER_NAME = "prod"

STATIC_ROOT = '/usr/src/xaas-admin/static/'
#STATIC_URL = 'https://github.com/django/django/blob/master/django/contrib/admin/static/'

#STATIC_ROOT = '/usr/local/lib/python3.6/site-packages/django/contrib/admin/static/'
