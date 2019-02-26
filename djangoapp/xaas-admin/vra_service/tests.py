from django.test import TestCase

from vra_service.models import VRAEventSubWorkflow, VRAService, VRAEventSubscriptionConditions


class ModelTest(TestCase):

    def setUp(self):

        item_req_workflow = VRAEventSubWorkflow.objects.create(vra_event_sub_workflow_name="NewItemWorkflow")

        vra_service = VRAService.objects.create(vra_svc_short_name='MyVM',
                                                vra_svc_long_name="Virtualization Server",
                                                vra_svc_description="Server virtualization hosting",
                                                vra_svc_item_req_ev_sub_wrkflw_id=item_req_workflow)

        ev_sub_cond = VRAEventSubscriptionConditions.objects.create(vra_event_sub_workflow_id=item_req_workflow,
                                                                    vra_service=vra_service,
                                                                    vra_event_sub_cond_left_operand="left.operand",
                                                                    vra_event_sub_cond_operator='equals',
                                                                    vra_event_sub_cond_right_operand="value")

    def test_string_representation(self):

        vra_service = VRAService.objects.get(vra_svc_short_name="MyVM")

        self.assertEqual(str(vra_service), "{} ({})".format(vra_service.vra_svc_long_name,
                                                            vra_service.vra_svc_short_name))

        item_req_workflow = VRAEventSubWorkflow.objects.get(vra_event_sub_workflow_name=vra_service.vra_svc_item_req_ev_sub_wrkflw_id)

        self.assertEqual(str(item_req_workflow), "NewItemWorkflow")
