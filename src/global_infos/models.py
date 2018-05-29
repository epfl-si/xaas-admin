"""(c) All rights reserved. ECOLE POLYTECHNIQUE FEDERALE DE LAUSANNE, Switzerland, VPSI, 2018"""
from django.db import models


class FacultyAdmin(models.Model):

    g_faculty = models.CharField(max_length=50, db_column="g_faculty", primary_key=True)
    g_ad_group = models.CharField(max_length=50, db_column="g_ad_group")

    class Meta:
        db_table = "glob_faculty_admins"


    def __str__(self):
        return self.g_faculty
