"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class VRAEventSubWorkflow(models.Model):

    vra_event_sub_vro_workflow = models.CharField(max_length=50,
                                                  db_column="vra_event_sub_workflow_name",
                                                  verbose_name="vRO workflow name")

    class Meta:
        db_table = "vra_event_sub_workflow"
        verbose_name = "vRA Event Subscription Workflow"
        verbose_name_plural = "vRA Event Subscription Workflows"

    def __str__(self):
        return self.vra_event_sub_vro_workflow


class VRAService(models.Model):

    vra_svc_short_name = models.CharField(max_length=20,
                                          db_column="vra_svc_short_name",
                                          verbose_name="Service short name",
                                          primary_key=True)
    vra_svc_long_name = models.CharField(max_length=50,
                                         db_column="vra_svc_long_name",
                                         verbose_name="Service long name")
    vra_svc_description = models.CharField(max_length=255,
                                           db_column="vra_svc_description",
                                           verbose_name="Service description")

    vra_svc_item_req_ev_sub_wrkflw_id = models.ForeignKey('vra_service.VRAEventSubWorkflow',
                                                          verbose_name="Item request Event Subscription Workflow")

    vra_svc_action_req_ev_sub_wrkflw_id = models.ForeignKey('vra_service.VRAEventSubWorkflow',
                                                            verbose_name="Action request Event Subscription Workflow")

    class Meta:
        db_table = "vra_service"
        verbose_name = "vRA Service"
        verbose_name_plural = "vRA Services"

    def __str__(self):
        return "{} ({})".format(self.vra_svc_long_name, self.vra_svc_short_name)


class VRAEventSubscriptionConditions(models.Model):

    operator_choices = (
        ('equals', 'Equals'),
        ('notEquals', 'Not equals'),
        ('contains', 'Contains'),
        ('startsWith', 'Starts with'),
        ('endsWith', 'Ends with'),
        ('within', 'Within')
    )

    vra_service = models.ForeignKey('vra_service.VRAService',
                                    db_column="vra_svc_long_name",
                                    verbose_name="When request for vRA Service...")

    vra_event_sub_workflow_id = models.ForeignKey('vra_service.VRAEventSubWorkflow',
                                                  verbose_name="... execute vRO Workflow")

    vra_event_sub_cond_left_operand = models.CharField(max_length=255,
                                                       db_column="vra_event_sub_cond_left_operand",
                                                       verbose_name="If vRO properties (path)")

    vra_event_sub_cond_operator = models.CharField(max_length=15,
                                                   db_column="vra_event_sub_cond_operator",
                                                   verbose_name="Operator",
                                                   choices=operator_choices)

    vra_event_sub_cond_right_operand = models.CharField(max_length=255,
                                                        db_column="vra_event_sub_cond_right_operand",
                                                        verbose_name="Value")

    class Meta:
        db_table = "vra_event_sub_conditions"
        verbose_name = "vRO Workflow exec condition"
        verbose_name_plural = "vRO Workflow exec conditions"

    def __str__(self):
        return "{}: exec {} if '{}' {} '{}'".format(self.vra_service,
                                                    self.vra_event_sub_workflow_id,
                                                    self.vra_event_sub_cond_left_operand,
                                                    self.vra_event_sub_cond_operator,
                                                    self.vra_event_sub_cond_right_operand)