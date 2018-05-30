from django.test import TestCase

from global_infos.models import FacultyAdmin


class ModelTest(TestCase):

    def setUp(self):
        faculty_admin = FacultyAdmin.objects.create(g_faculty="si", g_ad_group="vra_p_approval_si")

    def test_string_representation(self):

        faculty_admin = FacultyAdmin.objects.get(g_faculty="si")
        self.assertEqual(str(faculty_admin), faculty_admin.g_faculty)
