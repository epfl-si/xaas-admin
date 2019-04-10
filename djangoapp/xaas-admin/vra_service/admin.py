"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.contrib import admin
from vra_service.models import VRAEventSubWorkflow, VRAService, VRAEventSubscriptionConditions


class VRAEventSubWorkflowsAdmin(admin.ModelAdmin):
    """ To manage Event Subscription Workflows in Django-Admin """
    pass


admin.site.register(VRAEventSubWorkflow, VRAEventSubWorkflowsAdmin)


class VRAServicesAdmin(admin.ModelAdmin):
    """ To manage vRA Services in Django-Admin """
    pass


admin.site.register(VRAService, VRAServicesAdmin)


class VRAEventSubscriptionConditionsAdmin(admin.ModelAdmin):
    """ To manage vRA Services in Django-Admin """
    pass


admin.site.register(VRAEventSubscriptionConditions, VRAEventSubscriptionConditionsAdmin)
