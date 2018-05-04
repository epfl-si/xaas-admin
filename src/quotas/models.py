"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class MyVMQuota(models.Model):

    year = models.IntegerField()
    cpu_number = models.IntegerField()
    ram_mb = models.IntegerField()
    hdd_gb = models.IntegerField()
    cpu_nb_used = models.IntegerField()

    def __str__(self):
        return self.year
