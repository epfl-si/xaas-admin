"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from itservices.models import Service



class ServiceAdmin(admin.ModelAdmin):
    """ To manage Services in Django-Admin """
    pass


admin.site.register(Service, ServiceAdmin)
