"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from its.models import Services



class ServicesAdmin(admin.ModelAdmin):
    """ To manage Services in Django-Admin """
    pass


admin.site.register(Services, ServicesAdmin)
