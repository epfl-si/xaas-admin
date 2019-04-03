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

# Because we're on production, we add 'whitenoise' middleware in the list. And we have to add it right after
# 'SecurityMiddleware', as requested in documentation -> http://whitenoise.evans.io/en/stable/django.html
for index, mid in enumerate(MIDDLEWARE):

    if mid == 'django.middleware.security.SecurityMiddleware':
        MIDDLEWARE.insert(index+1, 'whitenoise.middleware.WhiteNoiseMiddleware')
        break


SERVER_NAME = "prod"