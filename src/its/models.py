"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class Services(models.Model):

    its_serv_short_name = models.CharField(max_length=20, db_column="its_serv_short_name", unique=True)
    its_serv_long_name = models.CharField(max_length=100, db_column="its_serv_long_name")
    its_serv_snow_id = models.CharField(max_length=100, db_column="its_serv_snow_id")

    class Meta:
        db_table = "its_services"

    def __str__(self):
        return self.its_serv_short_name
