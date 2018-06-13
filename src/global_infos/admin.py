"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from global_infos.models import Faculty


class FacultyAdmin(admin.ModelAdmin):
    """ To manage Faculty in Django-Admin """
    pass


admin.site.register(Faculty, FacultyAdmin)
