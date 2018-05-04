"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.conf.urls import url
from django.contrib import admin
from django_tequila.urls import urlpatterns as django_tequila_urlpatterns
from django_tequila.admin import TequilaAdminSite

admin.autodiscover()
admin.site.__class__ = TequilaAdminSite

urlpatterns = [
    url('admin/', admin.site.urls),
]

urlpatterns += django_tequila_urlpatterns
