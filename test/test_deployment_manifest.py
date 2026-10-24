"""Exercise the receipt-driven manifest command without signing or network access."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ADDRESS = "0x" + "11" * 20
ROUTER = "0x" + "22" * 20
CODEHASH = "0x" + "33" * 32
TX = "0x" + "44" * 32
ROUTER_TX = "0x" + "55" * 32
ZERO = "0x" + "00" * 20

CAST = r'''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
mode = os.environ.get("SCENARIO", "success")
address = "0x" + "11" * 20
router = "0x" + "22" * 20
codehash = "0x" + "33" * 32
if mode == "rpc-error":
    print("private endpoint failure", file=sys.stderr)
    sys.exit(1)
if a[0] == "chain-id": print(1 if mode == "wrong-chain" else 4663)
elif a[0] == "receipt":
    is_router = a[1] == "0x" + "55" * 32
    if mode == "partial" and is_router: sys.exit(1)
    print(json.dumps({
        "transactionHash": a[1] if mode != "wrong-tx" else "0x" + "66" * 32,
        "status": "0x0" if mode == "reverted" else "0x1",
        "blockNumber": None if mode == "pending" else "0x10",
        "blockHash": "0x" + "77" * 32,
        "contractAddress": None if mode == "wrong-address" else router if is_router else address,
    }))
elif a[0] == "code": print("0x" if mode == "missing-code" else "0x6002" if mode == "wrong-code" else "0x6000")
elif a[0] == "tx": print(json.dumps({"to": None, "input": "0x6001" if mode == "wrong-constructor" else "0x6000"}))
elif a[0] == "keccak": print("0x" + "00" * 32 if a[1] in ("0x6001", "0x6002") else codehash)
elif a[0] == "call":
    signature = a[2]
    if signature == "getMinDelay()(uint256)": print(0 if mode == "wrong-delay" else 86400)
    elif signature == "hasRole(bytes32,address)(bool)": print("false" if mode == "wrong-role" else "true")
    elif signature.endswith("(bytes32)"): print("0x" + "88" * 32)
    else: print(router if mode == "wrong-dependency" else address)
else: sys.exit(2)
'''


class DeploymentManifestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.candidate = self.directory / "operator-fee-router.candidate.json"
        self.destination = self.directory / "operator-fee-router.json"
        self.cast = self.directory / "cast"
        self.cast.write_text(CAST)
        self.cast.chmod(0o700)
        self.candidate.write_text(json.dumps({
            "chainId": 4663, "timelockDelay": 86400,
            "router": ROUTER, "timelock": ADDRESS, "operatorCollection": ADDRESS,
            "activationRegistry": ADDRESS, "operatorVault": ADDRESS,
            "timelockProposer": ADDRESS, "timelockExecutor": ZERO,
            "routerCodehash": CODEHASH, "timelockCodehash": CODEHASH,
            "routerCreationCodehash": CODEHASH, "timelockCreationCodehash": CODEHASH,
        }))

    def run_command(self, scenario="success"):
        return subprocess.run(
            ["bash", str(ROOT / "script/finalize-router-deployment.sh"), TX, ROUTER_TX, str(self.candidate)],
            env={**os.environ, "CAST_BIN": str(self.cast), "ROBINHOOD_MAINNET": "unused-test-endpoint",
                 "SCENARIO": scenario}, capture_output=True, text=True,
        )

    def test_success_records_both_confirmed_receipts(self):
        result = self.run_command()
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads(self.destination.read_text())
        self.assertEqual(manifest["deploymentReceipts"]["router"]["transactionHash"], ROUTER_TX)
        self.assertEqual(manifest["deploymentReceipts"]["timelock"]["contractAddress"], ADDRESS)
        self.assertNotIn("deploymentReceipts", json.loads(self.candidate.read_text()))

    def test_failed_validation_preserves_existing_manifest(self):
        original = '{"previous": "confirmed deployment"}'
        for scenario in ("rpc-error", "wrong-chain", "reverted", "pending", "partial", "wrong-tx",
                         "wrong-address", "missing-code", "wrong-code", "wrong-delay", "wrong-role",
                         "wrong-dependency", "wrong-constructor"):
            with self.subTest(scenario=scenario):
                self.destination.write_text(original)
                result = self.run_command(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.destination.read_text(), original)
                self.assertNotIn("private endpoint", result.stderr)
                self.assertEqual(list(self.directory.glob(".router-manifest-*")), [])

    def test_invalid_candidate_creates_no_manifest(self):
        self.candidate.write_text('{"chainId": 4663}')
        self.assertNotEqual(self.run_command().returncode, 0)
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
