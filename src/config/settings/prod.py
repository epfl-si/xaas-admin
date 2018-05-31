"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""

from .base import *  # noqa

DEBUG = False

ALLOWED_HOSTS = [
    'xaas-admin-test.epfl.ch',
    'exopgesrv34.epfl.ch',
]

# Database
# https://docs.djangoproject.com/en/2.0/ref/settings/#databases

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'HOST': get_secret('DB_HOST'),  # noqa
        'NAME': 'xaas_admin_prod',
        'USER': 'xaas_admin_user',
        'PASSWORD': get_secret('DB_USER_PWD'),  # noqa
        'PORT': get_secret('DB_PORT'),  # noqa
    }
}

SERVER_NAME = "prod"

STATIC_ROOT = '/var/www/vhosts/xaas-admin.epfl.ch/htdocs/'
