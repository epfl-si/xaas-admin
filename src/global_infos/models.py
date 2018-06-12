"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models

class Faculty(models.Model):

    g_faculty = models.CharField(max_length=50,
                                 db_column="g_faculty",
                                 verbose_name="Faculty",
                                 primary_key=True)

    class Meta:
        db_table = "glob_inf_faculty"
        verbose_name_plural = "Faculties"

    def __str__(self):
        return self.g_faculty
