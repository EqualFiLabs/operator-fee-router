#!/usr/bin/env python3
"""Receipt-backed local-only rehearsal. Standard library orchestration; cast executes transactions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
RAY = 10**27
MAX = 2**96 - 1
ZERO = '0x' + '00'*20
Z32 = '0x' + '00'*32
BINDINGS = {
    'collection': '0xad5E9F96A91D1A6F550580b157af2068A0e8F0BE',
    'registry': '0xfC62e99CaE93878f83801f3d6Bb4f1762E720B30',
    'vault': '0x8AAAF9a22f439589987B8f1e69d79ca4f648C297',
    'statics': '0x2d8d6F4A93AcD7a916A5a654ec8b690bA3B3EAdd',
    'weth': '0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73',
}

def dump(path, value):
    path = Path(path)
    temp = path.with_suffix(path.suffix + '.new')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    temp.replace(path)


def redact(text):
    secret = os.environ.get('ROBINHOOD_MAINNET', '')
    if secret:
        text = text.replace(secret, '[upstream RPC]')
    return re.sub(r'https?://[^\s"\'<>]+', '[RPC URL]', text)


def rpc(url, method, params):
    payload = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, payload, {'Content-Type': 'application/json'}), timeout=120) as f:
            answer = json.load(f)
        if 'error' in answer:
            raise RuntimeError(redact(json.dumps(answer['error'])))
        return answer['result']
    except Exception as exc:
        raise RuntimeError(redact(str(exc))) from None


def local_url(url):
    u = urlparse(url)
    if u.scheme != 'http' or u.hostname != '127.0.0.1' or not u.port or u.username or u.password or u.path not in ('', '/') or u.query or u.fragment:
        raise ValueError('writes require a plain numeric loopback HTTP endpoint')


def command(args, env=None):
    result = subprocess.run([str(x) for x in args], cwd=ROOT, text=True, capture_output=True, env=env)
    if result.returncode:
        raise RuntimeError(redact(result.stderr[-5000:] + result.stdout[-3000:]))
    return result.stdout.strip()


def words(data):
    body = data.removeprefix('0x')
    if len(body) % 64:
        raise ValueError('non-word ABI response')
    return [int(body[i:i+64], 16) for i in range(0, len(body), 64)]


def address(word):
    return '0x' + f'{word:040x}'


def runtime_matches(artifact, deployed):
    template = bytearray.fromhex(artifact['deployedBytecode']['object'].removeprefix('0x'))
    actual = bytes.fromhex(deployed.removeprefix('0x'))
    if len(template) != len(actual):
        return False
    for spans in artifact['deployedBytecode'].get('immutableReferences', {}).values():
        for span in spans:
            i, n = span['start'], span['length']
            template[i:i+n] = actual[i:i+n]
    return template == actual


def serve(args):
    """Detached supervisor keeps the fork alive and redacts all child output."""
    os.umask(0o077)
    run = Path(args.directory)
    upstream = os.environ['ROBINHOOD_MAINNET']
    argv = ['anvil', '--fork-url', upstream, '--fork-block-number', str(args.block),
            '--chain-id', '4663', '--host', '127.0.0.1', '--port', str(args.port),
            '--hardfork', 'cancun', '--steps-tracing', '--silent']
    with (run / 'anvil.log').open('a') as log:
        child = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        dump(run / 'service.json', {'supervisorPid': os.getpid(), 'anvilPid': child.pid, 'port': args.port,
                                    'block': args.block, 'token': args.token})
        def finish(*_):
            child.terminate()
        signal.signal(signal.SIGTERM, finish)
        signal.signal(signal.SIGINT, finish)
        for line in child.stdout:
            log.write(redact(line))
            log.flush()
        child.wait()


class Campaign:
    def __init__(self, args):
        os.umask(0o077)
        self.args = args
        self.run = ROOT / '.rehearsal-results' / (time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + os.urandom(3).hex())
        self.run.mkdir(parents=True)
        self.url = f'http://127.0.0.1:{args.port}'
        local_url(self.url)
        self.records, self.checks, self.assets, self.deployments = [], [], [], {}
        self.phase = 'preflight'
        self.cache = {}
        self.reads = 0
        self.env = dict(os.environ, FOUNDRY_OUT=str(self.run / 'out'), FOUNDRY_CACHE_PATH=str(self.run / 'cache'))
        print(f'Private evidence: {self.run}', flush=True)

    def check(self, label, condition, **data):
        record = {'phase': self.phase, 'check': label, 'passed': bool(condition), **data}
        self.checks.append(record)
        with (self.run / 'checks.jsonl').open('a') as f:
            f.write(json.dumps(record) + '\n')
        if not condition:
            raise AssertionError(label + ': ' + str(data))

    def begin(self, name):
        self.phase = name
        print(f'[{name}] {len(self.records)} transactions, {len(self.checks)} checks', flush=True)

    def guard(self):
        local_url(self.url)
        if 'anvil' not in rpc(self.url, 'web3_clientVersion', []).lower() or int(rpc(self.url, 'eth_chainId', []), 16) != 4663:
            raise RuntimeError('local Anvil identity guard failed')
        block = rpc(self.url, 'eth_getBlockByNumber', [hex(self.block), False])
        if not block or block['hash'] != self.anchor['hash']:
            raise RuntimeError('fork anchor guard failed')
        token = rpc(self.url, 'eth_getBalance', [self.marker, 'latest'])
        if int(token, 16) != self.token:
            raise RuntimeError('run ownership marker failed')

    def mutate(self, method, params):
        self.guard()
        if not method.startswith(('anvil_', 'evm_')):
            raise ValueError('unsupported control mutation')
        before = rpc(self.url, 'eth_blockNumber', [])
        result = rpc(self.url, method, params)
        with (self.run/'controls.jsonl').open('a') as f:
            f.write(json.dumps({'phase':self.phase,'method':method,'params':params,'result':result,'beforeBlock':before})+'\n')
        return result

    def data(self, sig, *args):
        key = (sig, tuple(str(x) for x in args))
        if key not in self.cache:
            self.cache[key] = command(['cast', 'calldata', sig, *map(str, args)])
        return self.cache[key]

    def view(self, target, sig, *args):
        data = self.data(sig, *args)
        block = rpc(self.url, 'eth_blockNumber', [])
        result = rpc(self.url, 'eth_call', [{'to': target, 'data': data}, block])
        self.reads += 1
        with (self.run / 'reads.jsonl').open('a') as f:
            f.write(json.dumps({'phase': self.phase, 'to': target, 'input': data, 'blockNumber': block, 'output': result}) + '\n')
        return words(result)

    def one(self, target, sig, *args):
        return self.view(target, sig, *args)[0]

    def balance(self, asset, who):
        return self.one(asset, 'balanceOf(address)', who)

    def impersonate(self, who):
        if who.lower() == BINDINGS['vault'].lower():
            raise RuntimeError('canonical vault cannot be gas-seeded or used as a top-level signer')
        self.mutate('anvil_impersonateAccount', [who])
        self.mutate('anvil_setBalance', [who, hex(10**23)])

    def send(self, target, sig=None, *args, sender=None, error=None, value=0, raw=None, label=None, gas=30_000_000):
        self.guard()
        sender = sender or self.actor
        data = raw if raw is not None else (self.data(sig, *args) if sig else '0x')
        argv = ['cast', 'send', '--rpc-url', self.url, '--unlocked', '--from', sender,
                '--gas-limit', str(gas), '--async', '--value', str(value)]
        if target:
            argv += [target, '--data', data]
        else:
            argv += ['--create', data]
        tx = command(argv)
        if not re.fullmatch('0x[0-9a-fA-F]{64}', tx):
            raise RuntimeError('cast did not return one transaction hash')
        receipt = None
        for _ in range(120):
            receipt = rpc(self.url, 'eth_getTransactionReceipt', [tx])
            if receipt:
                break
            time.sleep(.25)
        if not receipt:
            raise RuntimeError('transaction receipt deadline exceeded')
        transaction = rpc(self.url, 'eth_getTransactionByHash', [tx])
        trace = rpc(self.url, 'debug_traceTransaction', [tx, {'tracer': 'callTracer'}])
        number = len(self.records) + 1
        record = {'sequence': number, 'phase': self.phase, 'label': label or sig or 'deployment',
                  'expectedError': error, 'receipt': receipt, 'transaction': transaction, 'trace': trace}
        dump(self.run / f'tx-{number:05d}.json', record)
        self.records.append(record)
        ok = int(receipt['status'], 16) == (0 if error else 1)
        self.check('cast payload matches mined transaction', transaction['input'].lower() == data.lower() and transaction['from'].lower() == sender.lower() and (not target or transaction['to'].lower() == target.lower()))
        self.check('receipt status: ' + (label or sig or 'deployment'), ok, tx=tx, status=receipt['status'])
        if error:
            selector = command(['cast', 'sig', error])
            output = trace.get('output', '0x')
            self.check('exact revert selector', output.startswith(selector), expected=selector, output=output[:138])
        return receipt

    def artifact(self, name):
        matches = list((self.run / 'out').glob(f'*/{name}.json'))
        if len(matches) != 1:
            raise RuntimeError(f'ambiguous or missing artifact {name}')
        return json.loads(matches[0].read_text())

    def deploy(self, name, signature=None, *args):
        artifact = self.artifact(name)
        init = artifact['bytecode']['object']
        if signature:
            init += command(['cast', 'abi-encode', signature, *map(str, args)])[2:]
        receipt = self.send(None, raw=init, label='deploy ' + name)
        deployed = receipt['contractAddress']
        code = rpc(self.url, 'eth_getCode', [deployed, 'latest'])
        self.check('compiled runtime: ' + name, runtime_matches(artifact, code))
        self.deployments[deployed] = {'contract': name, 'runtimeHash': command(['cast', 'keccak', code]),
                                      'creationHash': command(['cast', 'keccak', init])}
        dump(self.run / 'deployments.json', self.deployments)
        return deployed

    def book(self, asset):
        return self.view(self.router, 'rewardBook(address)', asset)

    def audit(self, label, canonical=False, assets=None):
        total = self.one(self.router, 'totalEffectiveWeight()')
        chosen = self.assets if assets is None else assets
        # Include an empty asset to verify the full installed set even before registration.
        for asset in chosen or [ZERO]:
            b = self.book(asset)
            weight = scaled = ready = mismatch = 0
            for start in range(1, 5556, 100):
                row = self.view(self.probe, 'scan(address,address,uint256,uint256,bool)', self.router, asset,
                                start, min(100, 5556-start), str(canonical).lower())
                weight += row[0]; scaled += row[1]; ready += row[2]; mismatch += row[3]
            self.check(label + ': all Operator weights', weight == total and ready == 5555, weight=weight, total=total, initialized=ready)
            if canonical:
                self.check(label + ': canonical installation', mismatch == 0, mismatches=mismatch)
            if asset == ZERO:
                continue
            expired = self.one(self.router, 'expiredRewards(address)', asset)
            self.check(label + ': added = claimed + liability + expired', b[2] == b[3] + b[4] + expired, asset=asset)
            bal = self.balance(asset, self.router)
            self.check(label + ': balance covers liability', bal >= b[4], asset=asset, balance=bal, liability=b[4])
            self.check(label + ': exact available surplus', self.one(self.router, 'availableSurplus(address)', asset) == bal - b[4], asset=asset)
            if b[7]:
                self.check(label + ': complete scaled conservation', b[4]*RAY == scaled + b[1], asset=asset, left=b[4]*RAY, right=scaled+b[1])
            self.check(label + ': normalized book remainder', b[6] < RAY and b[1] < 5555*12500, asset=asset)
        count = self.one(self.router, 'rewardAssetCount()')
        registered = [address(self.one(self.router, 'rewardAssetAt(uint256)', i)) for i in range(count)]
        self.check(label + ': unique bounded registry', len(set(registered)) == count <= 64)
        self.check(label + ': registry agrees with books', set(registered) == {a.lower() for a in self.assets if self.book(a)[7]})

    def snapshot_financial(self, asset, ids):
        return {'book': self.book(asset), 'balance': self.balance(asset, self.router),
                'total': self.one(self.router, 'totalEffectiveWeight()'),
                'operators': [self.view(self.router, 'operatorState(uint256)', i) + self.view(self.router, 'operatorAssetState(uint256,address)', i, asset)
                              + self.view(self.router, 'pendingForfeiture(uint256,address)', i, asset) for i in ids]}

    def fail(self, target, sig, *args, error, asset=None, sender=None, value=0):
        before = self.snapshot_financial(asset, self.ids[:2]) if asset else None
        receipt = self.send(target, sig, *args, sender=sender, error=error, value=value)
        if asset:
            self.check('revert preserves financial state', before == self.snapshot_financial(asset, self.ids[:2]))
        return receipt

    def warp(self, seconds):
        self.mutate('evm_increaseTime', [seconds])
        self.mutate('evm_mine', [])

    def register(self, asset):
        self.send(self.router, 'registerRewardAsset(address)', asset, sender=self.gov)
        if asset not in self.assets:
            self.assets.append(asset)
        self.send(asset, 'approve(address,uint256)', self.router, 2**256-1)

    def mint(self, asset, amount):
        if self.deployments.get(asset,{}).get('contract') not in ('RehearsalToken','RehearsalFalseToken','MockFeeToken','MockSenderFeeToken'):
            raise RuntimeError('minting is restricted to locally deployed synthetic assets')
        self.send(asset, 'mint(address,uint256)', self.actor, amount)

    def add(self, asset, amount):
        before = self.book(asset)
        balance = self.balance(asset, self.router)
        sender = self.balance(asset, self.actor)
        weight = self.one(self.router, 'totalEffectiveWeight()')
        self.send(self.router, 'addRewards(address,uint256)', asset, amount)
        after = self.book(asset)
        q, rem = divmod(amount*RAY + before[1], weight)
        self.check('deposit exact deltas and independent index', after[:5] == [before[0]+q, rem, before[2]+amount, before[3], before[4]+amount]
                   and self.balance(asset, self.router) == balance+amount and self.balance(asset, self.actor) == sender-amount)

    def claim(self, operator, asset, receiver=None):
        owner = address(self.one(BINDINGS['collection'], 'ownerOf(uint256)', operator))
        return self.claim_as(operator, asset, owner, receiver or owner)

    def claim_as(self, operator, asset, owner, receiver):
        expected = self.one(self.router, 'pendingOperatorRewards(uint256,address)', operator, asset)
        before = self.balance(asset, receiver)
        self.impersonate(owner)
        receipt = self.send(self.router, 'claimOperatorRewards(uint256,address,address)', operator, asset, receiver, sender=owner)
        self.check('claim measured receiver delta', self.balance(asset, receiver)-before == expected, amount=expected)
        return receipt

    def schedule(self, target, data, *, salt=None, error=None):
        salt = salt or command(['cast', 'keccak', f'{self.phase}-{len(self.records)}'])
        self.send(self.timelock, 'schedule(address,uint256,bytes,bytes32,bytes32,uint256)', target, 0, data, Z32, salt, 86400,
                  sender=self.gov, error=error)
        return (target, 0, data, Z32, salt)

    def execute(self, operation, error=None):
        return self.send(self.timelock, 'execute(address,uint256,bytes,bytes32,bytes32)', *operation, error=error)

    def governed(self, target, sig, *args, error=None):
        op = self.schedule(target, self.data(sig, *args))
        self.warp(86401)
        self.execute(op, error)
        return op

    def prepare(self):
        upstream = os.environ.get('ROBINHOOD_MAINNET')
        if not upstream:
            raise RuntimeError('ROBINHOOD_MAINNET must be loaded before running')
        self.check('upstream chain identity', int(rpc(upstream, 'eth_chainId', []),16) == 4663)
        self.anchor = rpc(upstream, 'eth_getBlockByNumber', [hex(self.args.block) if self.args.block else 'latest', False])
        self.block = int(self.anchor['number'],16)
        code = {}
        for key, who in BINDINGS.items():
            data = rpc(upstream, 'eth_getCode', [who, self.anchor['number']])
            self.check('upstream code: ' + key, len(data) > 2)
            code[key] = command(['cast', 'keccak', data])
        # Historical state must actually be executable, not just a retrievable header.
        rpc(upstream, 'eth_call', [{'to': BINDINGS['collection'], 'data': self.data('ownerOf(uint256)', 1)}, self.anchor['number']])
        with socket.socket() as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(('127.0.0.1', self.args.port))
        self.token = int.from_bytes(os.urandom(12), 'big')
        self.marker = '0x00000000000000000000000000000000feed4663'
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), 'serve', str(self.run), '--block', str(self.block),
                          '--port', str(self.args.port), '--token', str(self.token)], cwd=ROOT,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(120):
            try:
                if 'anvil' in rpc(self.url, 'web3_clientVersion', []).lower():
                    break
            except RuntimeError:
                time.sleep(.5)
        else:
            raise RuntimeError('Anvil startup deadline exceeded; see redacted service log')
        # Initial ownership marker established only after client, chain and anchor checks.
        self.check('initial local chain', int(rpc(self.url, 'eth_chainId', []),16) == 4663)
        self.check('initial fork hash', rpc(self.url, 'eth_getBlockByNumber', [hex(self.block),False])['hash'] == self.anchor['hash'])
        rpc(self.url, 'anvil_setBalance', [self.marker, hex(self.token)])
        self.guard()
        # Familiar development addresses may carry real delegated code at the fork anchor.
        accounts = ['0x'+hashlib.sha256(f'{self.token}:{role}'.encode()).hexdigest()[-40:]
                    for role in ('deployer','proposer','buyer','other')]
        self.actor, self.gov, self.buyer, self.other = accounts
        for who in accounts:
            self.check('fresh actor has no inherited code',rpc(self.url,'eth_getCode',[who,'latest'])=='0x')
            self.impersonate(who)
        self.metadata = {'sourceCommit': command(['git','rev-parse','HEAD']), 'sourceDirty': command(['git','status','--porcelain']),
                         'fork': {k:self.anchor[k] for k in ('number','hash','timestamp','gasLimit')}, 'chainId':4663,
                         'canonicalBindings': BINDINGS, 'canonicalRuntimeHashes': code,
                         'tools': {x:command([x,'--version']) for x in ('forge','cast','anvil')},
                         'seed':self.args.seed, 'steps':self.args.steps, 'localEndpoint':self.url,
                         'assumptions':['local impersonation; no Safe signature validation', 'synthetic hostile assets are explicitly labeled',
                                        'no canonical storage or code replacement'], 'status':'running'}
        dump(self.run / 'manifest.json', self.metadata)
        self.begin('compile and deployment')
        config = json.loads(command(['forge','config','--json'], env=self.env))
        self.metadata['compilerSettings'] = {key:config.get(key) for key in ('solc','evm_version','optimizer','optimizer_runs','via_ir','bytecode_hash')}
        self.metadata['sourceHashes'] = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                                         for pattern in ('src/**/*.sol','test/rehearsal/*.sol','scripts/mainnet-rehearsal/*.py')
                                         for p in sorted(ROOT.glob(pattern))}
        dump(self.run/'manifest.json',self.metadata)
        log = command(['forge','build','--build-info'], env=self.env)
        (self.run / 'build.log').write_text(redact(log))
        self.metadata['compilerVersion'] = self.artifact('OperatorFeeRouter')['metadata']['compiler']['version']
        dump(self.run/'manifest.json',self.metadata)
        self.probe = self.deploy('RehearsalProbe')
        self.timelock = self.deploy('OperatorFeeRouterTimelock','constructor(address[],address[])', f'[{self.gov}]', f'[{ZERO}]')
        self.router = self.deploy('OperatorFeeRouter','constructor(address,address,address,address)',
                                  BINDINGS['collection'],BINDINGS['registry'],BINDINGS['vault'],self.timelock)
        for key, sig in [('collection','operatorCollection()'),('registry','activationRegistry()'),('vault','operatorVault()')]:
            self.check('router immutable '+key, address(self.one(self.router,sig)) == BINDINGS[key].lower())
        self.check('router timelock immutable',address(self.one(self.router,'routerTimelock()')) == self.timelock.lower())
        for target,sig,expected in [(BINDINGS['collection'],'COLLECTION_SIZE()',5555),
                                    (BINDINGS['collection'],'vault()',int(BINDINGS['vault'],16)),
                                    (BINDINGS['collection'],'activationRegistry()',int(BINDINGS['registry'],16)),
                                    (BINDINGS['registry'],'genesisCollection()',int(BINDINGS['collection'],16)),
                                    (BINDINGS['registry'],'statics()',int(BINDINGS['statics'],16))]:
            self.check('canonical binding '+sig,self.one(target,sig)==expected)
        self.ids=[]
        start=1
        while len(self.ids)<4 and start<=5555:
            found, owner, _ = self.view(self.probe,'candidate(address,address,address,uint256,uint256)',
                                       BINDINGS['collection'],BINDINGS['registry'],BINDINGS['vault'],start,min(100,5556-start))
            if found:
                self.ids.append(found); start=found+1; self.impersonate(address(owner))
            else: start+=100
        self.check('four unlocked canonical Operators found',len(self.ids)==4,ids=self.ids)
        dump(self.run/'actors.json',{'deployer':self.actor,'proposer':self.gov,'buyer':self.buyer,'operators':self.ids,
                                    'router':self.router,'timelock':self.timelock,'probe':self.probe})

    def report(self, status, failure=None):
        passed = sum(int(x['receipt']['status'],16)==1 for x in self.records)
        result = {'status':status,'phase':self.phase,'transactions':len(self.records),'successfulReceipts':passed,
                  'expectedReverts':sum(x['expectedError'] is not None for x in self.records),
                  'checks':len(self.checks),'passedChecks':sum(x['passed'] for x in self.checks),
                  'recordedReads':self.reads,'failure':failure, 'localEndpoint':self.url}
        dump(self.run/'summary.json',result)
        if hasattr(self,'metadata'):
            self.metadata['status']=status; dump(self.run/'manifest.json',self.metadata)
        print(json.dumps(result,indent=2),flush=True)


def stop(args):
    run=Path(args.directory).resolve()
    service=json.loads((run/'service.json').read_text())
    pid=service['supervisorPid']
    cmdline=Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
    if b'serve' not in cmdline or str(run).encode() not in cmdline or str(service['token']).encode() not in cmdline:
        raise RuntimeError('service ownership verification failed')
    os.kill(pid,signal.SIGTERM)
    for _ in range(100):
        with socket.socket() as sock:
            if sock.connect_ex(('127.0.0.1', service['port'])) != 0:
                print('Owned fork stopped')
                return
        time.sleep(.1)
    raise RuntimeError('owned service has not stopped yet')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='action',required=True)
    run=commands.add_parser('run'); run.add_argument('--port',type=int,default=18663)
    run.add_argument('--block',type=int); run.add_argument('--seed',type=int,default=4663)
    run.add_argument('--steps',type=int,default=160)
    service=commands.add_parser('serve'); service.add_argument('directory'); service.add_argument('--block',type=int,required=True)
    service.add_argument('--port',type=int,required=True); service.add_argument('--token',required=True)
    stopping=commands.add_parser('stop'); stopping.add_argument('directory')
    args=parser.parse_args()
    if args.action=='serve': return serve(args)
    if args.action=='stop': return stop(args)
    campaign=Campaign(args)
    try:
        campaign.prepare()
        from scenarios import exercise
        exercise(campaign)
        campaign.report('complete' if args.steps >= 160 else 'diagnostic')
        if args.steps >= 160:
            from verify import validate
            dump(campaign.run/'offline-verification.json',validate(campaign.run))
    except Exception as exc:
        campaign.report('failed',redact(str(exc)))
        raise SystemExit(1)

if __name__=='__main__': main()
