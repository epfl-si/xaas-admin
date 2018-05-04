"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from quotas.models import MyVMQuota


class MyVMQuotaAdmin(admin.ModelAdmin):
    """ To manage MyVMQuotas in Django-Admin """
    pass


admin.site.register(MyVMQuota, MyVMQuotaAdmin)
