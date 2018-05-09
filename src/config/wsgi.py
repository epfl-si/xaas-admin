import os
import sys

activate_this = '/home/kis/xaas-admin/bin/activate_this.py'
exec(open(activate_this).read(), dict(__file__=activate_this))

path = '/var/www/vhosts/xaas-admin.epfl.ch/private/src'
if path not in sys.path:
    sys.path.append(path)

os.environ['DJANGO_SETTINGS_MODULE'] = 'config.settings.test'
os.environ['TMPDIR'] = '/var/www/vhosts/xaas-admin.epfl.ch/private/tmpffi'
# os.environ['GEM_HOME'] = '/var/www/vhosts/homepage.epfl.ch/private/ruby/'


from django.core.wsgi import get_wsgi_application  # noqa
application = get_wsgi_application()