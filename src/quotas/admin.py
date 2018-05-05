"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from quotas.models import MyVMQuota, FacultyAdmin, ItsAdmin


class MyVMQuotaAdmin(admin.ModelAdmin):
    """ To manage MyVMQuotas in Django-Admin """
    pass


admin.site.register(MyVMQuota, MyVMQuotaAdmin)


class FacultyAdminAdmin(admin.ModelAdmin):
    """ To manage FacultyAdmin in Django-Admin """
    pass


admin.site.register(FacultyAdmin, FacultyAdminAdmin)


class ItsAdminAdmin(admin.ModelAdmin):
    """ To manage ItsAdmin in Django-Admin """
    pass


admin.site.register(ItsAdmin, ItsAdminAdmin)
