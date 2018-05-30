"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from global_infos.models import FacultyAdmin


class FacultyAdminAdmin(admin.ModelAdmin):
    """ To manage FacultyAdmin in Django-Admin """
    pass


admin.site.register(FacultyAdmin, FacultyAdminAdmin)
