from django.test import TestCase

from quotas.models import ItsAdmin


class ItsAdminModelTest(TestCase):

    def setUp(self):
        ItsAdmin.objects.create(active_directory_group="idevelop")

    def test_string_representation(self):
        its_admin = ItsAdmin.objects.get(active_directory_group="idevelop")
        self.assertEqual(str(its_admin), its_admin.active_directory_group)
