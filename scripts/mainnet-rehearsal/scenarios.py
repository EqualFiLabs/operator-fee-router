"""Scenario definitions; all writes go through Campaign's guarded cast sender."""
import random
from rehearse import BINDINGS as B, MAX, RAY, ZERO, Z32, address, command, dump


def bootstrap(c):
    c.begin('bootstrap boundaries and full canonical installation')
    init=c.artifact('OperatorFeeRouter')['bytecode']['object']
    init+=command(['cast','abi-encode','constructor(address,address,address,address)',B['collection'],B['registry'],c.probe,c.timelock])[2:]
    c.send(None,raw=init,label='reject inconsistent constructor binding',error='InvalidCollectionVault(address,address)')
    r=c.router; w=B['weth']
    c.register(w)
    for count in (0,101):
        c.fail(r,'bootstrapOperators(uint256)',count,error='InvalidBootstrapCount(uint256)')
    c.fail(r,'finalizeBootstrap()',error='BootstrapIncomplete(uint256)')
    c.fail(r,'addRewards(address,uint256)',w,1,error='BootstrapNotFinalized()')
    c.fail(r,'syncOperator(uint256)',1,error='OperatorNotInitialized(uint256)')
    for _ in range(56): c.send(r,'bootstrapOperators(uint256)',100)
    c.check('complete bootstrap cursor',c.one(r,'nextOperatorId()')==5556)
    c.send(r,'finalizeBootstrap()')
    c.fail(r,'finalizeBootstrap()',error='BootstrapAlreadyFinalized()')
    c.fail(r,'bootstrapOperators(uint256)',1,error='BootstrapAlreadyFinalized()')
    c.audit('bootstrap',canonical=True)


def ingress_and_auth(c):
    c.begin('reward ingress, claims and authorization')
    r=c.router; w=B['weth']; i=c.ids[0]
    c.send(w,'deposit()',value=50*10**18)
    c.add(w,10**18+13)
    c.claim(i,w,c.buyer)
    c.fail(r,'claimOperatorRewards(uint256,address,address)',i,w,c.buyer,sender=c.buyer,
           error='NotOperatorOwner(uint256,address,address)',asset=w)
    c.fail(r,'claimOperatorRewards(uint256,address,address)',i,w,c.buyer,
           sender=address(c.one(B['collection'],'ownerOf(uint256)',i)),error='NoRewards()',asset=w)
    for receiver in (ZERO,r):
        c.fail(r,'claimOperatorRewards(uint256,address,address)',i,w,receiver,error='InvalidReceiver(address)',asset=w)
    c.fail(r,'addRewards(address,uint256)',w,0,error='ZeroAmount()',asset=w)
    c.fail(r,'registerRewardAsset(address)',w,error='Unauthorized(address)')
    c.fail(r,'registerRewardAsset(address)',w,sender=c.gov,error='RewardAssetAlreadyRegistered(address)')
    c.fail(r,'registerRewardAsset(address)',c.other,sender=c.gov,error='AddressHasNoCode(address)')
    c.fail(r,'setRewardAssetEnabled(address,bool)',w,'false',error='Unauthorized(address)')
    c.fail(r,'deregisterRewardAsset(address)',w,sender=c.gov,error='Unauthorized(address)')
    c.fail(r,'recoverSurplus(address,address,uint256)',w,c.actor,1,sender=c.gov,error='Unauthorized(address)',asset=w)
    c.fail(r,None,value=1,error='NativeAssetUnsupported()')
    for invalid in (0,5556,2**256-1):
        c.fail(r,'syncOperator(uint256)',invalid,error='OperatorNotInitialized(uint256)')
    c.fail(r,'flushPendingForfeiture(uint256,address)',i,w,error='NoPendingForfeiture(uint256,address)')
    c.audit('ingress and claims')


def canonical_lifecycle(c):
    c.begin('canonical activation, transfers, vault redemption and reacquisition')
    r=c.router; w=B['weth']; nft=B['collection']; registry=B['registry']; token=B['statics']; vault=B['vault']
    c.check('live STATICS decimals',c.one(token,'decimals()')==18)
    treasury=address(c.one(registry,'treasury()'))
    c.impersonate(treasury)
    chosen=next((i for i in c.ids if c.one(registry,'tierOf(uint256)',i)<4),None)
    c.check('activation candidate below max tier',chosen is not None)
    owner=address(c.one(nft,'ownerOf(uint256)',chosen)); tier=c.one(registry,'tierOf(uint256)',chosen)
    cost=c.one(registry,'tierCost(uint8)',tier+1)
    if c.balance(token,owner)<cost:
        short=cost-c.balance(token,owner)
        c.check('real treasury can fund activation',c.balance(token,treasury)>=short)
        c.send(token,'transfer(address,uint256)',owner,short,sender=treasury)
    c.impersonate(owner)
    c.send(token,'approve(address,uint256)',registry,cost,sender=owner)
    before=c.one(r,'pendingOperatorRewards(uint256,address)',chosen,w)
    weight=c.one(r,'totalEffectiveWeight()'); old=c.one(r,'effectiveWeight(uint256)',chosen)
    c.send(registry,'activate(uint256,uint8)',chosen,tier+1,sender=owner)
    c.check('activation remains lazy until sync',c.one(r,'effectiveWeight(uint256)',chosen)==old)
    c.send(r,'syncOperator(uint256)',chosen)
    new=c.one(registry,'multiplierBps(uint256)',chosen)
    c.check('prospective activation preserves earned rewards',c.one(r,'pendingOperatorRewards(uint256,address)',chosen,w)==before)
    c.check('activation updates total exactly',c.one(r,'totalEffectiveWeight()')==weight-old+new)
    c.add(w,10**18+7)
    # NFT approval must not confer reward claim authority.
    c.send(nft,'approve(address,uint256)',c.buyer,chosen,sender=owner)
    c.fail(r,'claimOperatorRewards(uint256,address,address)',chosen,w,c.buyer,sender=c.buyer,
           error='NotOperatorOwner(uint256,address,address)',asset=w)
    prior=c.book(w)
    c.send(nft,'transferFrom(address,address,uint256)',owner,c.buyer,chosen,sender=owner)
    c.add(w,10**12+3)  # Revenue arriving before ownership synchronization must also forfeit correctly.
    prior=c.book(w)
    c.check('canonical transfer resets activation',c.one(registry,'tierOf(uint256)',chosen)==0)
    c.check('stale owner has no pending view reward',c.one(r,'pendingOperatorRewards(uint256,address)',chosen,w)==0)
    c.fail(r,'claimOperatorRewards(uint256,address,address)',chosen,w,owner,sender=owner,
           error='NotOperatorOwner(uint256,address,address)',asset=w)
    c.claim(chosen,w,c.buyer)  # Zero payout commits transfer detection and forfeiture.
    c.check('transfer recorded forfeiture',c.book(w)[5]>prior[5] and c.book(w)[4]==prior[4])
    c.check('new owner installed',address(c.one(r,'syncedOwner(uint256)',chosen))==c.buyer.lower())
    c.add(w,10**15+1)
    c.claim(chosen,w,c.other)
    c.audit('activation and transfer',canonical=True)
    # Use another unlocked, unencumbered canonical NFT for a full backing/reserve round trip.
    i=next(i for i in reversed(c.ids) if i!=chosen)
    owner=address(c.one(nft,'ownerOf(uint256)',i)); c.impersonate(owner)
    c.check('no vault credit on redeemed Operator',c.one(vault,'creditActive(uint256)',i)==0)
    backing=c.one(vault,'tokenBacking()'); reserve=c.one(vault,'reserveETH()')
    payout=c.one(vault,'reserveRedemptionPayout()') if not c.one(vault,'epochActive()') else 0
    price=c.one(vault,'vaultPrice()')
    start=c.balance(token,c.actor)
    c.send(nft,'approve(address,uint256)',vault,i,sender=owner)
    c.send(vault,'redeemGenesis(uint256,address)',i,c.actor,sender=owner)
    c.check('real backing paid on redemption',c.balance(token,c.actor)==start+price and c.one(vault,'tokenBacking()')==backing-price)
    c.check('real reserve accounting on redemption',c.one(vault,'reserveETH()')==reserve-payout)
    c.send(r,'syncOperator(uint256)',i)
    c.check('vault inventory excluded from weight',c.one(r,'effectiveWeight(uint256)',i)==0)
    c.send(token,'approve(address,uint256)',vault,price)
    required=(c.one(vault,'reserveBuyIn()') if not c.one(vault,'epochActive()') else 0)+c.one(vault,'nativeAcquisitionFee()')
    c.send(vault,'buyGenesis(uint256,address)',i,c.other,value=required)
    c.send(r,'syncOperator(uint256)',i)
    c.check('reacquired Operator base weight',c.one(r,'effectiveWeight(uint256)',i)==10000)
    c.check('backing restored by purchase',c.one(vault,'tokenBacking()')==backing)
    c.check('canonical vault remains solvent',c.balance(token,vault)>=c.one(vault,'requiredBacking()'))
    c.audit('vault round trip',canonical=True)
    # Exercise a second real revenue rail without synthetic ERC-20 balance overrides.
    c.register(token)
    c.check('real treasury can fund STATICS rewards',c.balance(token,treasury)>=2*10**18)
    c.send(token,'transfer(address,uint256)',c.actor,2*10**18,sender=treasury)
    c.add(token,10**18+17)
    c.claim(chosen,token,c.other)
    c.audit('real STATICS revenue')


def hostile_assets(c):
    c.begin('hostile assets, exact transfers, callbacks and arithmetic limits')
    r=c.router
    high=c.deploy('RehearsalToken','constructor(uint8)',19)
    c.fail(r,'registerRewardAsset(address)',high,sender=c.gov,error='UnsupportedRewardAssetDecimals(address,uint8)')
    c.reward=c.deploy('RehearsalToken','constructor(uint8)',0)
    c.register(c.reward); c.mint(c.reward,MAX+10000)
    for amount in (1,2,7,13,97,5555): c.add(c.reward,amount)
    # Confirm the cap is on outstanding liability rather than lifetime deposits.
    outstanding=c.book(c.reward)[4]
    c.add(c.reward,MAX-outstanding)
    c.fail(r,'addRewards(address,uint256)',c.reward,1,error='RewardLiabilityLimitExceeded(address,uint256,uint256,uint256)',asset=c.reward)
    c.claim(c.ids[0],c.reward)
    c.add(c.reward,1)
    c.audit('uint96 boundary and sub-token conservation')
    for contract in ('MockFeeToken','MockSenderFeeToken'):
        asset=c.deploy(contract); c.register(asset); c.mint(asset,10**22)
        c.send(asset,'setFeeEnabled(bool)','true')
        c.fail(r,'addRewards(address,uint256)',asset,10**18,error='InexactTokenTransfer(address,uint256,uint256,uint256)',asset=asset)
        c.send(asset,'setFeeEnabled(bool)','false'); c.add(asset,10**18)
        c.send(asset,'setFeeEnabled(bool)','true')
        i=c.ids[1]; owner=address(c.one(B['collection'],'ownerOf(uint256)',i)); c.impersonate(owner)
        c.fail(r,'claimOperatorRewards(uint256,address,address)',i,asset,owner,sender=owner,
               error='InexactTokenTransfer(address,uint256,uint256,uint256)',asset=asset)
        c.send(asset,'setFeeEnabled(bool)','false'); c.claim(i,asset)
    cb=c.deploy('RehearsalToken','constructor(uint8)',18); c.callback=cb
    c.register(cb); c.mint(cb,10**22)
    c.send(cb,'setCallback(address,bytes)',r,c.data('syncOperator(uint256)',c.ids[0]))
    c.add(cb,10**18)
    c.check('ingress callback attempted and rejected',c.one(cb,'callbackAttempted()')==1 and c.one(cb,'callbackSucceeded()')==0)
    c.send(cb,'setCallback(address,bytes)',r,c.data('syncOperator(uint256)',c.ids[0]))
    c.claim(c.ids[1],cb)
    c.check('outbound callback attempted and rejected',c.one(cb,'callbackAttempted()')==1 and c.one(cb,'callbackSucceeded()')==0)
    false=c.deploy('RehearsalFalseToken');c.register(false);c.mint(false,10**22)
    c.send(false,'setFalseReturn(bool)','true')
    c.fail(r,'addRewards(address,uint256)',false,10**18,error='SafeERC20FailedOperation(address)',asset=false)
    c.send(false,'setFalseReturn(bool)','false');c.add(false,10**18)
    c.send(false,'setFalseReturn(bool)','true')
    i=c.ids[1];owner=address(c.one(B['collection'],'ownerOf(uint256)',i));c.impersonate(owner)
    c.fail(r,'claimOperatorRewards(uint256,address,address)',i,false,owner,sender=owner,error='SafeERC20FailedOperation(address)',asset=false)
    c.send(false,'setFalseReturn(bool)','false');c.claim(i,false)
    c.audit('hostile token conservation')


def governance(c):
    c.begin('claim-only, expiry, recovery and timelock operations')
    r=c.router; t=c.timelock; a=c.callback
    c.send(r,'setRewardAssetEnabled(address,bool)',a,'false',sender=c.gov)
    c.send(r,'setRewardAssetEnabled(address,bool)',a,'false',sender=c.gov)  # idempotence
    c.fail(r,'addRewards(address,uint256)',a,1,error='RewardAssetDisabled(address)',asset=a)
    c.claim(c.ids[0],a)
    c.send(r,'setRewardAssetEnabled(address,bool)',a,'true',sender=c.gov); c.add(a,71)
    c.send(r,'setRewardAssetEnabled(address,bool)',a,'false',sender=c.gov)
    c.send(a,'transfer(address,uint256)',r,123)
    liability=c.book(a)[4]
    c.governed(r,'recoverSurplus(address,address,uint256)',a,c.actor,124,error='InsufficientSurplus(address,uint256,uint256)')
    c.governed(r,'recoverSurplus(address,address,uint256)',a,c.actor,123)
    # A failed second call must roll back the first recovery in a timelock batch.
    w=B['weth'];c.send(w,'transfer(address,uint256)',r,41)
    data1=c.data('recoverSurplus(address,address,uint256)',w,c.actor,41)
    data2=c.data('recoverSurplus(address,address,uint256)',w,c.actor,1)
    targets=f'[{r},{r}]'; values='[0,0]'; payloads=f'[{data1},{data2}]'
    salt=command(['cast','keccak','batch rollback'])
    c.send(t,'scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)',targets,values,payloads,Z32,salt,86400,sender=c.gov)
    c.warp(86401)
    financial=c.snapshot_financial(w,c.ids)
    receiver=c.balance(w,c.actor)
    c.send(t,'executeBatch(address[],uint256[],bytes[],bytes32,bytes32)',targets,values,payloads,Z32,salt,
           error='InsufficientSurplus(address,uint256,uint256)')
    c.check('batch rollback preserves custody and receiver',financial==c.snapshot_financial(w,c.ids) and receiver==c.balance(w,c.actor))
    c.governed(r,'recoverSurplus(address,address,uint256)',w,c.actor,41)
    salt=command(['cast','keccak','successful governance batch'])
    one=c.data('setRewardAssetEnabled(address,bool)',w,'false')
    two=c.data('setRewardAssetEnabled(address,bool)',w,'true')
    payloads=f'[{one},{two}]'
    c.send(t,'scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)',targets,values,payloads,Z32,salt,86400,sender=c.gov)
    c.warp(86401)
    c.send(t,'executeBatch(address[],uint256[],bytes[],bytes32,bytes32)',targets,values,payloads,Z32,salt)
    c.check('successful batch restores active state',c.one(r,'rewardAssetEnabled(address)',w)==1)
    c.governed(r,'deregisterRewardAsset(address)',w,error='RewardAssetNotClaimOnly(address)')
    c.fail(t,'schedule(address,uint256,bytes,bytes32,bytes32,uint256)',r,0,data1,Z32,salt,0,sender=c.gov,
           error='TimelockInsufficientDelay(uint256,uint256)')
    c.fail(t,'schedule(address,uint256,bytes,bytes32,bytes32,uint256)',r,0,data1,Z32,salt,86400,
           error='AccessControlUnauthorizedAccount(address,bytes32)')
    c.check('recovery preserves liabilities',c.book(a)[4]==liability and c.balance(a,r)==liability)
    op=c.schedule(r,c.data('deregisterRewardAsset(address)',a))
    c.execute(op,error='TimelockUnexpectedOperationState(bytes32,bytes32)')
    opid='0x'+f"{c.one(t,'hashOperation(address,uint256,bytes,bytes32,bytes32)',*op):064x}"
    c.send(t,'cancel(bytes32)',opid,sender=c.gov)
    c.warp(86401)
    c.execute(op,error='TimelockUnexpectedOperationState(bytes32,bytes32)')
    op=c.schedule(r,c.data('deregisterRewardAsset(address)',a)); c.warp(86401)
    # Broken outbound token cannot obstruct expiry: deregistration makes no token transfer.
    c.send(a,'setBlocked(bool)','true')
    owner=address(c.one(B['collection'],'ownerOf(uint256)',c.ids[2]));c.impersonate(owner)
    c.check('blocked-transfer claimant has earned rewards',c.one(r,'pendingOperatorRewards(uint256,address)',c.ids[2],a)>0)
    c.fail(r,'claimOperatorRewards(uint256,address,address)',c.ids[2],a,owner,sender=owner,error='Error(string)',asset=a)
    c.execute(op)
    c.check('expiry exact liability',c.one(r,'expiredRewards(address)',a)==liability and c.book(a)[4]==0)
    c.fail(r,'registerRewardAsset(address)',a,sender=c.gov,error='RewardAssetPermanentlyDeregistered(address)')
    c.fail(r,'claimOperatorRewards(uint256,address,address)',c.ids[0],a,c.actor,error='RewardAssetNotRegistered(address)',asset=a)
    c.fail(r,'setRewardAssetEnabled(address,bool)',a,'true',sender=c.gov,error='RewardAssetNotRegistered(address)')
    c.send(a,'setBlocked(bool)','false')
    c.governed(r,'recoverSurplus(address,address,uint256)',a,c.actor,liability)
    c.check('expired funds recovered',c.balance(a,r)==0)
    c.governed(t,'updateDelay(uint256)',86399,error='TimelockDelayBelowMinimum(uint256,uint256)')
    c.fail(t,'updateDelay(uint256)',86400,error='TimelockUnauthorizedCaller(address)')
    c.governed(t,'updateDelay(uint256)',86400)
    proposer=c.one(t,'PROPOSER_ROLE()'); canceller=c.one(t,'CANCELLER_ROLE()')
    role='0x'+f'{proposer:064x}'; cancel='0x'+f'{canceller:064x}'
    c.governed(t,'grantRole(bytes32,address)',role,c.other)
    c.check('proposer grant couples canceller',c.one(t,'hasRole(bytes32,address)',cancel,c.other)==1)
    c.governed(t,'revokeRole(bytes32,address)',role,c.other)
    c.check('proposer revoke removes canceller',c.one(t,'hasRole(bytes32,address)',cancel,c.other)==0)
    c.governed(t,'grantRole(bytes32,address)',role,c.other)
    c.send(t,'renounceRole(bytes32,address)',role,c.other,sender=c.other)
    c.check('proposer renunciation removes canceller',c.one(t,'hasRole(bytes32,address)',cancel,c.other)==0)
    c.audit('expiry and governance')


def capacity(c):
    c.begin('64-asset capacity and cold synchronization gas')
    r=c.router
    while c.one(r,'rewardAssetCount()')<64:
        a=c.deploy('RehearsalToken','constructor(uint8)',18)
        c.register(a); c.mint(a,10**12); c.add(a,10**12)
    extra=c.deploy('RehearsalToken','constructor(uint8)',18)
    c.fail(r,'registerRewardAsset(address)',extra,sender=c.gov,error='RewardAssetLimitReached()')
    i=c.ids[0]; owner=address(c.one(B['collection'],'ownerOf(uint256)',i)); c.impersonate(owner)
    destination=c.buyer if owner.lower()!=c.buyer.lower() else c.other
    c.send(B['collection'],'transferFrom(address,address,uint256)',owner,destination,i,sender=owner)
    receipt=c.send(r,'syncOperator(uint256)',i)
    gas=int(receipt['gasUsed'],16)
    c.check('64-asset cold transfer synchronization gas budget',gas<15_000_000,gasUsed=gas,budget=15_000_000)
    # Claim-triggered sync must also fit, in an un-warmed separate transaction.
    for asset in c.assets:
        if not c.book(asset)[7]:continue
        if c.balance(asset,c.actor)<10**6:c.mint(asset,10**6)
        c.add(asset,10**6)
    c.send(B['collection'],'transferFrom(address,address,uint256)',destination,owner,i,sender=destination)
    receipt=c.claim(i,B['weth'])
    c.check('64-asset claim-triggered synchronization gas budget',int(receipt['gasUsed'],16)<15_000_000,gasUsed=int(receipt['gasUsed'],16))
    # Every populated asset, not just the WETH rail, is reconciled after the full-capacity churn.
    c.audit('full asset capacity',canonical=True)


def soak(c):
    c.begin('composed seeded stateful campaign')
    rng=random.Random(c.args.seed)
    r=c.router; w=B['weth']
    active=[w,c.reward]
    steps=[]
    for n in range(c.args.steps):
        i=rng.choice(c.ids); asset=rng.choice(active); action=rng.randrange(7)
        if action==0:
            amount=rng.choice([1,2,13,5555,10**12+17])
            if asset==c.reward:
                # Keep cap arithmetic active without relying on a fixed historical balance.
                room=MAX-c.book(asset)[4]; amount=min(amount,room)
                if not amount: action=1
                elif c.balance(asset,c.actor)<amount: c.mint(asset,amount)
            if action==0: c.add(asset,amount)
        if action==1:
            pending=c.one(r,'pendingOperatorRewards(uint256,address)',i,asset)
            if pending: c.claim(i,asset,c.other)
            else:
                owner=address(c.one(B['collection'],'ownerOf(uint256)',i));c.impersonate(owner)
                c.fail(r,'claimOperatorRewards(uint256,address,address)',i,asset,c.other,sender=owner,error='NoRewards()',asset=asset)
        elif action==2:
            owner=address(c.one(B['collection'],'ownerOf(uint256)',i));c.impersonate(owner)
            dest=c.buyer if owner.lower()!=c.buyer.lower() else c.other
            c.send(B['collection'],'transferFrom(address,address,uint256)',owner,dest,i,sender=owner)
            c.send(r,'syncOperator(uint256)',i)
        elif action==3:
            c.send(r,'syncOperator(uint256)',i)
        elif action==4:
            c.send(r,'setRewardAssetEnabled(address,bool)',w,'false',sender=c.gov)
            c.fail(r,'addRewards(address,uint256)',w,1,error='RewardAssetDisabled(address)',asset=w)
            c.send(r,'setRewardAssetEnabled(address,bool)',w,'true',sender=c.gov)
        elif action==5:
            c.fail(r,'recoverSurplus(address,address,uint256)',asset,c.actor,1,error='Unauthorized(address)',asset=asset)
        elif action==6:
            c.warp(rng.randrange(1,3601))
            c.send(w,'transfer(address,uint256)',r,rng.randrange(1,1000))
        # Audit hot rails after every action; full 64-asset scan after every transfer and at completion.
        c.audit(f'soak action {n}',assets=active)
        if action==2:
            c.audit(f'soak transfer {n}',assets=[a for a in c.assets if a not in active and c.book(a)[7]])
        steps.append({'step':n,'operator':i,'asset':asset,'action':action})
        dump(c.run/'soak-actions.json',steps)
        if n%20==0: print(f'  soak {n+1}/{c.args.steps}',flush=True)
    c.audit('composed campaign final',canonical=True)


def queue_fixture(c):
    c.begin('synthetic canonical scene: zero weight, queue and flush')
    # Fresh production router with explicit synthetic bindings; canonical mainnet contracts stay intact.
    original=(c.router,c.assets,c.ids)
    vault=c.deploy('MockVault')
    collection=c.deploy('MockOperatorCollection','constructor(address)',vault)
    registry=c.deploy('MockActivationRegistry','constructor(address)',collection)
    c.send(collection,'bindActivationRegistry(address)',registry)
    c.router=c.deploy('OperatorFeeRouter','constructor(address,address,address,address)',collection,registry,vault,c.timelock)
    c.assets=[];c.ids=[1,2]
    for _ in range(56): c.send(c.router,'bootstrapOperators(uint256)',100)
    c.send(c.router,'finalizeBootstrap()')
    a=c.deploy('RehearsalToken','constructor(uint8)',18);c.register(a);c.mint(a,1000001)
    c.fail(c.router,'addRewards(address,uint256)',a,1,error='ZeroEffectiveWeight()',asset=a)
    c.impersonate(vault)
    c.fail(c.router,'claimOperatorRewards(uint256,address,address)',1,a,c.actor,sender=vault,error='VaultCannotClaim(uint256)',asset=a)
    c.send(registry,'setMultiplier(uint256,uint16)',1,10001)
    c.send(collection,'setOwner(uint256,address)',1,c.actor);c.send(c.router,'syncOperator(uint256)',1)
    c.add(a,1000001)
    c.send(collection,'setOwner(uint256,address)',1,c.buyer);c.send(c.router,'syncOperator(uint256)',1)
    pending=c.view(c.router,'pendingForfeiture(uint256,address)',1,a)
    c.check('sole Operator fractional forfeiture queued exactly',pending[0]*RAY+pending[1]==1000001*RAY-c.book(a)[1] and pending[1]>0)
    c.fail(c.router,'flushPendingForfeiture(uint256,address)',1,a,error='NoOtherEffectiveWeight(uint256)',asset=a)
    c.send(collection,'setOwner(uint256,address)',2,c.other);c.send(c.router,'syncOperator(uint256)',2)
    c.send(c.router,'flushPendingForfeiture(uint256,address)',1,a)
    c.check('flush excludes originating Operator',c.one(c.router,'pendingOperatorRewards(uint256,address)',1,a)==0)
    c.check('flush gives other Operator entire queued amount',c.one(c.router,'pendingOperatorRewards(uint256,address)',2,a)==1000001)
    c.claim_as(2,a,c.other,c.other)
    c.audit('zero-weight queue fixture',canonical=True)
    c.router,c.assets,c.ids=original


def coverage(c):
    c.begin('ABI coverage evidence')
    # Observe every router getter directly at a recorded fork height.
    a=B['weth'];i=c.ids[0]
    for item in c.artifact('OperatorFeeRouter')['abi']:
        if item.get('type')!='function' or item['stateMutability'] not in ('view','pure'):continue
        sig=item['name']+'('+','.join(x['type'] for x in item['inputs'])+')'
        args=[]
        for value in item['inputs']:
            args.append(a if value['type']=='address' else (0 if item['name']=='rewardAssetAt' else i))
        c.view(c.router,sig,*args)
    for sig,args in [('MIN_DELAY()',[]),('getMinDelay()',[]),('DEFAULT_ADMIN_ROLE()',[]),('EXECUTOR_ROLE()',[]),
                     ('getRoleAdmin(bytes32)',[Z32]),('supportsInterface(bytes4)',['0x01ffc9a7']),
                     ('isOperation(bytes32)',[Z32]),('isOperationPending(bytes32)',[Z32]),('isOperationReady(bytes32)',[Z32]),
                     ('isOperationDone(bytes32)',[Z32]),('getTimestamp(bytes32)',[Z32]),('getOperationState(bytes32)',[Z32])]:
        c.view(c.timelock,sig,*args)
    rows={}
    for contract,target in [('OperatorFeeRouter',c.router),('OperatorFeeRouterTimelock',c.timelock)]:
        for item in c.artifact(contract)['abi']:
            if item.get('type')!='function':continue
            sig=item['name']+'('+','.join(x['type'] for x in item['inputs'])+')'
            selector=command(['cast','sig',sig]);key=contract+'.'+sig
            rows[key]={'selector':selector,'mutability':item['stateMutability'],'successfulTransactions':[],'revertedTransactions':[],'committedCalls':[],'reads':0}
            for rec in c.records:
                tx=rec['transaction']
                if tx.get('to','') and tx['to'].lower()==target.lower() and tx['input'].startswith(selector):
                    k='successfulTransactions' if int(rec['receipt']['status'],16) else 'revertedTransactions'
                    rows[key][k].append(rec['sequence'])
    def committed(trace, path=()):
        if trace.get('error'):return
        yield trace,path
        for n,child in enumerate(trace.get('calls',[])):
            yield from committed(child,path+(n,))
    for rec in c.records:
        if int(rec['receipt']['status'],16)!=1:continue
        for call,path in committed(rec['trace']):
            for key,row in rows.items():
                target=c.router if key.startswith('OperatorFeeRouter.') else c.timelock
                if call.get('to','').lower()==target.lower() and call.get('input','').startswith(row['selector']):
                    row['committedCalls'].append({'transaction':rec['sequence'],'callPath':list(path)})
    for line in (c.run/'reads.jsonl').read_text().splitlines():
        rec=__import__('json').loads(line)
        for key,row in rows.items():
            target=c.router if key.startswith('OperatorFeeRouter.') else c.timelock
            if rec['to'].lower()==target.lower() and rec['input'].startswith(row['selector']): row['reads']+=1
    dump(c.run/'selector-coverage.json',rows)
    # Router business writes must all have a successful transaction; fixture-only queue is explicitly noted.
    for name in ('bootstrapOperators','finalizeBootstrap','registerRewardAsset','setRewardAssetEnabled','deregisterRewardAsset',
                 'addRewards','syncOperator','claimOperatorRewards','recoverSurplus'):
        # Governance execution is nested; retain actual successful call traces rather than crediting the schedule.
        observed=False
        selector=next(v['selector'] for k,v in rows.items() if k.startswith('OperatorFeeRouter.'+name+'('))
        def walk(trace, committed=True):
            if not committed or trace.get('error'):return False
            if trace.get('to','').lower()==c.router.lower() and trace.get('input','').startswith(selector):return True
            return any(walk(t,True) for t in trace.get('calls',[]))
        observed=any(int(rec['receipt']['status'],16)==1 and walk(rec['trace']) for rec in c.records)
        c.check('observed committed router write '+name,observed)
    c.check('all router views observed',all(v['reads']>0 for k,v in rows.items() if k.startswith('OperatorFeeRouter.') and v['mutability'] in ('view','pure')))
    c.check('queue/flush exercised in labeled synthetic scene',any(x['label']=='flushPendingForfeiture(uint256,address)' and int(x['receipt']['status'],16)==1 for x in c.records))


def exercise(c):
    bootstrap(c)
    ingress_and_auth(c)
    canonical_lifecycle(c)
    hostile_assets(c)
    governance(c)
    capacity(c)
    soak(c)
    queue_fixture(c)
    coverage(c)
