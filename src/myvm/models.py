"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class MyVMStaticMAC(models.Model):

    myvm_static_mac_address = models.CharField(max_length=17, db_column="myvm_static_mac_address", unique=True)
    myvm_static_mac_used_by = models.CharField(max_length=36, db_column="myvm_static_mac_used_by", unique=True)

    class Meta:
        db_table = "myvm_static_mac"

    def __str__(self):
        return "{}={}".format(self.myvm_static_mac_address, self.myvm_static_mac_used_by)


class MyVMQuotas(models.Model):

    myvm_quotas_year = models.IntegerField(db_column="myvm_quotas_year")

    myvm_quotas_cpu_nb = models.IntegerField(db_column="myvm_quotas_cpu_nb")
    myvm_quotas_ram_mb = models.IntegerField(db_column="myvm_quotas_ram_mb")
    myvm_quotas_hdd_gb = models.IntegerField(db_column="myvm_quotas_hdd_gb")

    myvm_quotas_cpu_nb_used = models.IntegerField(db_column="myvm_quotas_cpu_nb_used")
    myvm_quotas_ram_mb_used = models.IntegerField(db_column="myvm_quotas_ram_mb_used")
    myvm_quotas_hdd_gb_used = models.IntegerField(db_column="myvm_quotas_hdd_gb_used")

    myvm_quotas_used_last_update = models.DateTimeField(db_column="myvm_quotas_used_last_update")

    myvm_quotas_cpu_nb_reserved = models.IntegerField(null=True, db_column="myvm_quotas_cpu_nb_reserved")
    myvm_quotas_ram_mb_reserved = models.IntegerField(null=True, db_column="myvm_quotas_ram_mb_reserved")
    myvm_quotas_hdd_gb_reserved = models.IntegerField(null=True, db_column="myvm_quotas_hdd_gb_reserved")

    myvm_faculty = models.ForeignKey('glob.FacultyAdmin', db_column="myvm_faculty")

    class Meta:
        unique_together = ('myvm_quotas_year', 'myvm_faculty')
        db_table = "myvm_quotas"

    def __str__(self):
        return "{}:{}".format(self.myvm_faculty, str(self.myvm_quotas_year))
