"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class ItsAdmin(models.Model):

    active_directory_group = models.CharField(max_length=50)

    def __str__(self):
        return self.active_directory_group


class FacultyAdmin(models.Model):

    name = models.CharField(max_length=50)
    active_directory_group = models.ForeignKey(ItsAdmin)

    def __str__(self):
        return self.name


class MyVMQuota(models.Model):

    year = models.IntegerField()
    cpu_number = models.IntegerField()
    ram_mb = models.IntegerField()
    hdd_gb = models.IntegerField()
    cpu_nb_used = models.IntegerField()
    ram_mb_used = models.IntegerField()
    hdd_gb_used = models.IntegerField()
    used_last_update = models.DateTimeField()
    cpu_nb_reserved = models.IntegerField()
    ram_mb_reserved = models.IntegerField()
    hdd_gb_reserved = models.IntegerField()

    faculty = models.ForeignKey(FacultyAdmin)

    def __str__(self):
        return self.year
