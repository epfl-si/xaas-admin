"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class Service(models.Model):

    its_serv_short_name = models.CharField(max_length=20,
                                           db_column="its_serv_short_name",
                                           verbose_name="Short name",
                                           primary_key=True)
    its_serv_long_name = models.CharField(max_length=100,
                                          db_column="its_serv_long_name",
                                          verbose_name="Long name")
    its_serv_snow_id = models.CharField(max_length=100,
                                        db_column="its_serv_snow_id",
                                        verbose_name="ServiceNow Service ID")

    class Meta:
        db_table = "its_services"
        verbose_name = "ITS Service"
        verbose_name_plural = "ITS Services"

    def __str__(self):
        return self.its_serv_short_name
