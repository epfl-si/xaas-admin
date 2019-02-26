from django.test import TestCase

from global_infos.models import Faculty
from myvm.models import MyVMQuota


class ModelTest(TestCase):

    def setUp(self):
        faculty_admin = Faculty.objects.create(g_faculty="si", g_ad_group="vra_p_approval_si")

        myvm_quotas = MyVMQuota.objects.create(myvm_faculty=faculty_admin,
                                               myvm_quotas_year=2018,
                                               myvm_quotas_cpu_nb=100,
                                               myvm_quotas_ram_mb=409600,
                                               myvm_quotas_hdd_gb=2000,
                                               myvm_quotas_cpu_nb_used=10,
                                               myvm_quotas_ram_mb_used=20480,
                                               myvm_quotas_hdd_gb_used=500,
                                               myvm_quotas_used_last_update="2018-05-28 12:00:00")

    def test_string_representation(self):
        faculty_admin = Faculty.objects.get(g_ad_group="vra_p_approval_si")
        self.assertEqual(str(faculty_admin), faculty_admin.g_faculty)

        myvm_quotas = MyVMQuota.objects.get(myvm_faculty="si", myvm_quotas_year=2018)
        self.assertEqual(str(myvm_quotas), "{}:{}".format(myvm_quotas.myvm_faculty, str(myvm_quotas.myvm_quotas_year)))
