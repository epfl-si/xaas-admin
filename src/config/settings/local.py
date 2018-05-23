"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""

from .base import *  # noqa

DEBUG = True

ALLOWED_HOSTS = [
    '127.0.0.1',
]

# Database
# https://docs.djangoproject.com/en/2.0/ref/settings/#databases
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': 'xaas-admin',
        'USER': 'xaas-admin',
        'PASSWORD': get_secret('DB_USER_PWD'),
    }
}

DEBUG_TOOLBAR_CONFIG = {
    'SHOW_TOOLBAR_CALLBACK': 'config.settings.local.custom_show_toolbar',
}

SERVER_NAME = "local"
