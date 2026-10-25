import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('verify',Path(__file__).with_name('verify.py'))
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.run=Path(self.temp.name)
        self.write('manifest.json',{'status':'complete','steps':160})
        self.write('summary.json',{'status':'complete','checks':8,'passedChecks':8,'transactions':1,
                                   'successfulReceipts':1,'expectedReverts':0})
        phases=['bootstrap boundaries and full canonical installation','canonical activation, transfers, vault redemption and reacquisition',
                'hostile assets, exact transfers, callbacks and arithmetic limits','claim-only, expiry, recovery and timelock operations',
                '64-asset capacity and cold synchronization gas','composed seeded stateful campaign',
                'synthetic canonical scene: zero weight, queue and flush','ABI coverage evidence']
        (self.run/'checks.jsonl').write_text(''.join(json.dumps({'phase':p,'passed':True})+'\n' for p in phases))
        self.write('tx-00001.json',{'sequence':1,'expectedError':None,'receipt':{'transactionHash':'tx','blockHash':'block',
                  'blockNumber':'0x1','status':'0x1'},'transaction':{'hash':'tx','blockHash':'block','blockNumber':'0x1'},'trace':{}})
        self.write('soak-actions.json',[{'action':i%7} for i in range(160)])
        self.write('selector-coverage.json',{'OperatorFeeRouter.totalEffectiveWeight()':{'mutability':'view','reads':1}})

    def tearDown(self): self.temp.cleanup()
    def write(self,name,value): (self.run/name).write_text(json.dumps(value))
    def test_valid_fixture(self): self.assertEqual(v.validate(self.run)['status'],'verified')
    def test_incomplete_campaign_cannot_pass(self):
        self.write('manifest.json',{'status':'complete','steps':0})
        with self.assertRaises(AssertionError): v.validate(self.run)
    def test_missing_receipt_cannot_pass(self):
        (self.run/'tx-00001.json').unlink()
        with self.assertRaises(AssertionError): v.validate(self.run)
    def test_reverted_root_is_not_successful_coverage(self):
        data=json.loads((self.run/'tx-00001.json').read_text());data['trace']['error']='execution reverted'
        self.write('tx-00001.json',data)
        with self.assertRaises(AssertionError): v.validate(self.run)
    def test_inclusion_mismatch_cannot_pass(self):
        data=json.loads((self.run/'tx-00001.json').read_text());data['transaction']['blockHash']='another'
        self.write('tx-00001.json',data)
        with self.assertRaises(AssertionError): v.validate(self.run)
    def test_unexercised_action_class_cannot_pass(self):
        self.write('soak-actions.json',[{'action':0}]*160)
        with self.assertRaises(AssertionError): v.validate(self.run)

    def test_nested_success_under_reverted_parent_is_rejected(self):
        data=json.loads((self.run/'tx-00001.json').read_text())
        data['trace']={'calls':[{'error':'reverted','calls':[{'input':'0xabcdef01'}]}]}
        self.write('tx-00001.json',data)
        self.write('selector-coverage.json',{'OperatorFeeRouter.addRewards(address,uint256)':
                   {'mutability':'nonpayable','selector':'0xabcdef01','committedCalls':[{'transaction':1,'callPath':[0,0]}]}})
        with self.assertRaises(AssertionError): v.validate(self.run)

    def test_committed_nested_call_is_accepted(self):
        data=json.loads((self.run/'tx-00001.json').read_text())
        data['trace']={'calls':[{'calls':[{'input':'0xabcdef01'}]}]}
        self.write('tx-00001.json',data)
        self.write('selector-coverage.json',{'OperatorFeeRouter.addRewards(address,uint256)':
                   {'mutability':'nonpayable','selector':'0xabcdef01','committedCalls':[{'transaction':1,'callPath':[0,0]}]}})
        self.assertEqual(v.validate(self.run)['status'],'verified')
