from django.test import TestCase

from quotas.models import ItsAdmin, FacultyAdmin, MyVMQuota


class ModelTest(TestCase):

    def setUp(self):
        its_admin = ItsAdmin.objects.create(active_directory_group="idevelop")
        faculty_admin = FacultyAdmin.objects.create(name="VPSI", its_admin=its_admin)
        MyVMQuota.objects.create(faculty=faculty_admin, year=2018)

    def test_string_representation(self):
        its_admin = ItsAdmin.objects.get(active_directory_group="idevelop")
        self.assertEqual(str(its_admin), its_admin.active_directory_group)

        faculty_admin = FacultyAdmin.objects.get(name="VPSI")
        self.assertEqual(str(faculty_admin), faculty_admin.name)

        my_vm_quota = MyVMQuota.objects.get(year=2018)
        self.assertEqual(str(my_vm_quota), str(my_vm_quota.year))
