from django.test import TestCase

from quotas.models import ItsAdmin, FacultyAdmin


class ItsAdminModelTest(TestCase):

    def setUp(self):
        its_admin = ItsAdmin.objects.create(active_directory_group="idevelop")
        FacultyAdmin.objects.create(name="VPSI", its_admin=its_admin)

    def test_string_representation(self):
        its_admin = ItsAdmin.objects.get(active_directory_group="idevelop")
        self.assertEqual(str(its_admin), its_admin.active_directory_group)

        faculty_admin = FacultyAdmin.objects.get(name="VPSI")
        self.assertEqual(str(faculty_admin), faculty_admin.name)
