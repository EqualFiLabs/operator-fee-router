#!/usr/bin/env python3
"""Check retained evidence without requiring a running fork or upstream RPC."""
import argparse
import json
from pathlib import Path


def validate(run):
    run=Path(run)
    manifest=json.loads((run/'manifest.json').read_text())
    summary=json.loads((run/'summary.json').read_text())
    checks=[json.loads(x) for x in (run/'checks.jsonl').read_text().splitlines()]
    assert summary['status']=='complete' and manifest['status']=='complete', 'campaign did not complete'
    assert manifest['steps']>=160, 'diagnostic campaigns are not a complete rehearsal'
    assert checks and all(x['passed'] is True for x in checks), 'failed or missing checks'
    assert summary['passedChecks']==summary['checks']==len(checks), 'check count mismatch'
    files=sorted(run.glob('tx-*.json'))
    assert len(files)==summary['transactions'], 'missing transaction evidence'
    good=bad=0
    records={}
    for n,path in enumerate(files,1):
        record=json.loads(path.read_text())
        assert record['sequence']==n, 'transaction sequence gap'
        records[n]=record
        receipt=record['receipt'];tx=record['transaction'];trace=record['trace']
        assert receipt['transactionHash']==tx['hash'], 'receipt and transaction disagree'
        assert receipt['blockHash']==tx['blockHash'] and receipt['blockNumber']==tx['blockNumber'], 'inclusion mismatch'
        expected=0 if record['expectedError'] else 1
        assert int(receipt['status'],16)==expected, 'unexpected receipt status'
        if expected:
            good+=1
            assert not trace.get('error'), 'successful receipt has failed root trace'
        else:
            bad+=1
            assert trace.get('error'), 'reverted receipt lacks reverted root trace'
    assert good==summary['successfulReceipts'] and bad==summary['expectedReverts'], 'receipt count mismatch'
    actions=json.loads((run/'soak-actions.json').read_text())
    assert len(actions)==manifest['steps'], 'incomplete stateful campaign'
    assert {x['action'] for x in actions}==set(range(7)), 'stateful action class was never exercised'
    coverage=json.loads((run/'selector-coverage.json').read_text())
    assert coverage, 'missing coverage ledger'
    for key,row in coverage.items():
        for observed in row.get('committedCalls',[]):
            record=records[observed['transaction']]
            assert int(record['receipt']['status'],16)==1, 'reverted transaction credited as successful coverage'
            node=record['trace']
            assert not node.get('error'), 'reverted root credited as committed call'
            for index in observed['callPath']:
                node=node['calls'][index]
                assert not node.get('error'), 'rolled-back nested call credited as committed'
            assert node.get('input','').startswith(row['selector']), 'coverage selector does not match call'
        if key.startswith('OperatorFeeRouter.') and row['mutability'] in ('view','pure'):
            assert row['reads']>0, 'unobserved router view: '+key
    required=['bootstrap boundaries and full canonical installation','canonical activation, transfers, vault redemption and reacquisition',
              'hostile assets, exact transfers, callbacks and arithmetic limits','claim-only, expiry, recovery and timelock operations',
              '64-asset capacity and cold synchronization gas','composed seeded stateful campaign',
              'synthetic canonical scene: zero weight, queue and flush','ABI coverage evidence']
    phases={x['phase'] for x in checks}
    assert all(x in phases for x in required), 'missing scenario phase'
    return {'status':'verified','transactions':len(files),'checks':len(checks),'statefulActions':len(actions)}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory')
    print(json.dumps(validate(parser.parse_args().directory),indent=2))
