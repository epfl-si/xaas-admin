"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class MyVMStaticMAC(models.Model):

    myvm_static_mac_address = models.CharField(max_length=17,
                                               db_column="myvm_static_mac_address",
                                               verbose_name="Static MAC Address",
                                               primary_key=True)
    myvm_static_mac_used_by = models.CharField(max_length=36,
                                               db_column="myvm_static_mac_used_by",
                                               verbose_name="Used by vRA VM ID")

    class Meta:
        db_table = "myvm_static_mac"
        verbose_name = "MyVM Static MAC"
        verbose_name_plural = "MyVM Static MAC"

    def __str__(self):
        return "{}={}".format(self.myvm_static_mac_address, self.myvm_static_mac_used_by)


class MyVMQuota(models.Model):

    myvm_quotas_year = models.IntegerField(db_column="myvm_quotas_year",
                                           verbose_name="Year")

    myvm_quotas_cpu_nb = models.IntegerField(db_column="myvm_quotas_cpu_nb",
                                             verbose_name="NB CPUs")
    myvm_quotas_ram_mb = models.IntegerField(db_column="myvm_quotas_ram_mb",
                                             verbose_name="RAM [MB]")
    myvm_quotas_hdd_gb = models.IntegerField(db_column="myvm_quotas_hdd_gb",
                                             verbose_name="HDD [GB]")

    myvm_quotas_cpu_nb_used = models.IntegerField(db_column="myvm_quotas_cpu_nb_used",
                                                  verbose_name="Used - NB CPUs",
                                                  default=0)
    myvm_quotas_ram_mb_used = models.IntegerField(db_column="myvm_quotas_ram_mb_used",
                                                  verbose_name="Used - RAM [MB]",
                                                  default=0)
    myvm_quotas_hdd_gb_used = models.IntegerField(db_column="myvm_quotas_hdd_gb_used",
                                                  verbose_name="Used - HDD [GB]",
                                                  default=0)

    myvm_quotas_used_last_update = models.DateTimeField(db_column="myvm_quotas_used_last_update",
                                                        verbose_name="Quota last update")

    myvm_quotas_cpu_nb_reserved = models.IntegerField(null=True,
                                                      db_column="myvm_quotas_cpu_nb_reserved",
                                                      verbose_name="Reserved - NB CPUs",
                                                      default=0)
    myvm_quotas_ram_mb_reserved = models.IntegerField(null=True,
                                                      db_column="myvm_quotas_ram_mb_reserved",
                                                      verbose_name="Reserved - RAM [MB]",
                                                      default=0)
    myvm_quotas_hdd_gb_reserved = models.IntegerField(null=True,
                                                      db_column="myvm_quotas_hdd_gb_reserved",
                                                      verbose_name="Reserved - HDD [GB]",
                                                      default=0)

    myvm_faculty = models.ForeignKey('global_infos.FacultyAdmin', db_column="myvm_faculty", verbose_name="Faculty")

    class Meta:
        unique_together = ('myvm_quotas_year', 'myvm_faculty')
        db_table = "myvm_quotas"
        verbose_name = "MyVM Quotas"
        verbose_name_plural = "MyVM Quotas"

    def __str__(self):
        return "{}:{}".format(self.myvm_faculty, str(self.myvm_quotas_year))
