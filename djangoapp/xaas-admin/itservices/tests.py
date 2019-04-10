from django.test import TestCase

from itservices.models import Service


class ModelTest(TestCase):

    def setUp(self):
        serv = Service.objects.create(its_serv_short_name="myvm",
                                      its_serv_long_name="Virtual server infrastructure",
                                      its_serv_snow_id="SVC0080")

    def test_string_representation(self):

        serv = Service.objects.get(its_serv_short_name="myvm")
        self.assertEqual(str(serv), serv.its_serv_short_name)
