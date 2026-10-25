import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('rehearse', Path(__file__).with_name('rehearse.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class SafetyTests(unittest.TestCase):
    def test_refuses_nonlocal_and_ambiguous_write_endpoints(self):
        for url in ('https://127.0.0.1:8545', 'http://localhost:8545', 'http://127.0.0.1.evil:8545',
                    'http://127.0.0.1:8545@evil', 'http://user@127.0.0.1:8545', 'http://127.0.0.1:8545/api',
                    'http://127.0.0.1:8545?upstream=1', 'http://[::1]:8545', 'http://127.0.0.1'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                r.local_url(url)
        r.local_url('http://127.0.0.1:18663')

    def test_runtime_match_rejects_mutation_outside_immutable(self):
        artifact = {'deployedBytecode': {'object': '0x0102030405',
                    'immutableReferences': {'17': [{'start': 1, 'length': 2}]}}}
        self.assertTrue(r.runtime_matches(artifact, '0x01ffff0405'))
        self.assertFalse(r.runtime_matches(artifact, '0x01ffff0406'))
        self.assertFalse(r.runtime_matches(artifact, '0x01ffff04'))
        without = copy.deepcopy(artifact)
        without['deployedBytecode']['immutableReferences'] = {}
        self.assertFalse(r.runtime_matches(without, '0x01ffff0405'))

    def test_secret_urls_do_not_survive_redaction(self):
        text = r.redact('upstream https://example.invalid/token?secret=yes failed')
        self.assertNotIn('secret', text)
        self.assertNotIn('example.invalid', text)

    def test_canonical_assets_cannot_be_synthetically_minted(self):
        c=r.Campaign.__new__(r.Campaign)
        c.deployments={}
        for asset in r.BINDINGS.values():
            with self.subTest(asset=asset), self.assertRaises(RuntimeError):
                c.mint(asset,1)

    def test_malformed_abi_response_is_rejected(self):
        with self.assertRaises(ValueError): r.words('0x01')
        self.assertEqual(r.words('0x'+'00'*31+'01'), [1])


if __name__ == '__main__': unittest.main()
