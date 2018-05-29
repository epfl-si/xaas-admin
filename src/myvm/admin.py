"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from myvm.models import MyVMQuota, MyVMStaticMAC


class MyVMQuotasAdmin(admin.ModelAdmin):
    """ To manage MyVMQuota in Django-Admin """
    pass


admin.site.register(MyVMQuota, MyVMQuotasAdmin)


class MyVMStaticMACAdmin(admin.ModelAdmin):
    """ To manage MyVM Static MAC in Django-Admin """
    pass


admin.site.register(MyVMStaticMAC, MyVMStaticMACAdmin)

