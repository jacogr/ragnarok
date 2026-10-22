# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 implications: immutable account/queue/staging/privilege writes, yields, provisions, deferred transfers and exceptional checkpoints.
## Exposes prepared pairs, guarded current accounts/info/queues/staging/privileges and controlled mutations with a versioned allocation cursor.
## Guest memory, gas, registers, execution verdicts and publication belong to their caller's PVM layer.

import std/[assertions, algorithm]
import ../codec/[bounded, composite, state_outputs, state_accounts, state_layout, state_requests,
    state_service_values, state_privileges, state_authorization, work_report, state_safrole, c2_records]
import ../chain/parameters
import ../crypto/primitives
import ./[accumulation_context, accumulation_invocation, accumulation_service, store, preimages]

const AccumulationAccountInfoBytes* = 112 ## Fixed Omega_I record, excluding serialized metadata's version byte.

type
  AccumulationEffectError* {.pure.} = enum ## No refused/default operation exposes a partial context, fabricated hash or successful empty owner.
    Uninitialized, None, InvalidContexts, InvalidDimension, YieldAbsent, UnknownService,
    NotRequested, AlreadyProvided, InvalidLength, InvalidState, MalformedState, LimitExceeded,
      BackendFailure, InvalidIndex,
      StorageFull,              ## Candidate storage footprint requires more balance than the account has.
      InvalidParameters,        ## Deposit settings must come from a valid parameter snapshot.
      NotManager,               ## Only the current privileged manager may replace the privilege state.
      AmbiguousPrivileges,      ## Conflicting gas values for one service have no pinned dictionary interpretation.
      InvalidCore,              ## The selected core is outside the current positional queue layout.
      NotAssigner,              ## Only the current assigner may replace its core queue.
      InvalidValidatorCount,    ## Staging population must be a supported multiple of three.
      NotDelegator,             ## Only the current delegator may replace the staging roster.
      InsufficientCash,         ## Account debits must preserve the creator's own minimum balance.
      ServiceExists,            ## A registrar-selected reserved service ID is already occupied.
      TransferGasLow,           ## Offered deferred gas is below the current destination minimum.
      ModifiedAccountsDisabled, ## The caller did not enable bounded modified-account tracking.
      CreatedAccountsDisabled,  ## Explicit creation facts require enabled bounded tracing.
      AccountWriteFactsDisabled ## The caller did not enable bounded physical account-write facts.
  AccumulationModifiedAccountIndex* = distinct uint64 ## Modification ordinal is distinct from a protocol service identity.
  # Immutable unique membership facts contain only fixed identities and no parent-effect owners.
  ModifiedAccountsData = ref object
    values: seq[ServiceIndex]
  AccumulationAccountWriteFactIndex* = distinct uint64 ## Physical fact ordinal is distinct from modification or self-key ordinals.
  AccumulationAccountWriteFact* = object ## Copied successful account/key binding; final value or deletion belongs to its producing context.
    service*: ServiceIndex ## Logical account that owns this actual successful write.
    key*: StateKey         ## Physical key copied from that account's genuine host operation.
  # Immutable fixed facts retain no account payloads or parent-effect owners.
  AccountWriteFactsData = ref object
    values: seq[AccumulationAccountWriteFact]
  AccumulationAccountScope* {.pure.} = enum ## Conservative mutation provenance since the credited initial context; equal bytes never reset it.
    Initial,         ## No account mutation occurred on this retained lineage.
    SelfMetadata,    ## Only supported metadata operations changed the invoking service's record.
    SelfEntries,     ## Bounded unique self storage/request keys accompany selected metadata.
    CreatedAccounts, ## Bounded creation proofs accompany supported self metadata/entries.
    DeletedAccounts, ## Bounded ejection proofs accompany supported self/created account changes.
    Unsupported      ## At least one broader mutation requires later publication support.
  AccumulationDeletedAccountIndex* = distinct uint64 ## A deletion ordinal cannot substitute a service identity or ejection target.
  AccumulationDeletedAccount* = object ## Copied successful-ejection facts; final absence is checked in the producing context.
    service*: ServiceIndex ## Actual target whose balance was reclaimed by this invocation.
  # Immutable fixed facts retain neither account values nor parent effect graphs.
  DeletedAccountsData = ref object
    values: seq[AccumulationDeletedAccount]
  AccumulationCreatedAccountIndex* = distinct uint64 ## A created-account ordinal cannot substitute a service identity.
  AccumulationCreatedAccount* = object ## Copied creation facts remain tied to their producing effect context for final-value extraction.
    service*: ServiceIndex ## Actual reserved/automatic ID chosen by a genuine successful new call.
    requestKey*: StateKey  ## Canonical empty code-request key captured by that exact creation.
  # Immutable creation membership contains fixed facts, never copied account values or parent effect versions.
  CreatedAccountsData = ref object
    values: seq[AccumulationCreatedAccount]
  AccumulationAccountWriteIndex* = distinct uint64 ## A traced key ordinal cannot substitute a service identity or raw storage key.
  # Only self operation implementations construct this immutable unique-key proof; values stay in the account snapshot.
  AccountKeysData = ref object
    keys: seq[StateKey]
  AccumulationEjectTarget* = distinct uint64 ## Full register identity; self and out-of-range values return WHO without narrowing.
  AccumulationTransferDestination* = distinct uint64 ## Full register domain; high bits are rejected as WHO before narrowing to ServiceIndex.
  AccumulationTransferIndex* = distinct uint64 ## Outgoing ordinal is neither a service identity nor a transfer amount.
  # Immutable ordered transfer backing is shared only by frozen effect versions.
  TransferSetData = ref object
    values: seq[DeferredTransfer]
  AccumulationDesiredService* = distinct uint64 ## Full-width proposal: only registrar values below 65536 select a reserved uint32 ID.
  AccumulationFundingMode* = distinct uint64 ## Full register mode: bit0 selects protected source, bit1 protected destination; values above3 are HUH.
  AccumulationNewService* = object ## Copied creation proposal; account identity, parent, slot and starting balance are derived by the state operation.
    codeHash*: CodeHash     ## Raw offered hash; creation neither requires nor publishes its preimage.
    length*: RequestLength  ## The encoded E4 length must exclude the two reserved namespace values.
    accumulationGas*: Gas   ## Minimum per-item gas, without signed narrowing.
    transferGas*: Gas       ## Minimum per-transfer gas, without signed narrowing.
    gratis*: AccountBalance ## Nonzero offset requires the current manager.
    desired*: AccumulationDesiredService ## Non-registrar or non-reserved proposals select automatic allocation.
  AccumulationProvisionIndex* = distinct uint64 ## A provision ordinal is neither its target service nor a byte count.
  AccumulationProvisionLimits* = object ## Independent ceilings bound retained records, individual hash/copy work and aggregate payload bytes.
    items*: ElementLimit
    perBlob*, totalBlobBytes*: ByteLimit
  ## Immutable provision backing binds the exact target to its independent raw-byte payload.
  ProvisionData = ref object
    service: ServiceIndex
    bytes: seq[byte]
  AccumulationProvision* = object ## Retained provision owns its original bytes and target; no detached span or caller-selected buffer is accepted.
    data: nil ProvisionData
  AccumulationProvisionInfo* = object ## Copied fixed facts never expose the provision's mutable backing sequence.
    service*: ServiceIndex
    bytes*: int
  ## Immutable set owner lets yield/checkpoint share provision membership without copying its sequence.
  ProvisionSetData = ref object
    values: seq[AccumulationProvision]
    bytes, largest: uint64
  ## Only a present alternative stores a commitment; absence cannot expose a default all-zero hash.
  YieldValue = object
    case present: bool
    of true:
      commitment: OutputCommitment # Zero bytes remain a present protocol value.
    of false:
      discard                      # Absence carries no commitment payload.
  EffectData = ref object # Current implications retain separate initial provenance, accounts, yield, provisions and transfers.
    initial: InitialAccumulationContext
    accounts: StateStoreSnapshot
    accountScope: AccumulationAccountScope
    modified: ModifiedAccountsData
    modifiedLimit: ElementLimit
    writeFacts: AccountWriteFactsData
    writeFactLimit: ElementLimit
    designated: bool # Successful designate provenance follows exact implication/checkpoint ownership.
    blessed: bool  # Successful bless provenance follows the same exact implication/checkpoint owner.
    assigned: bool # Successful assign provenance follows exact implication/checkpoint ownership.
    accountKeys: AccountKeysData
    accountKeyLimit: ElementLimit
    created: CreatedAccountsData
    createdLimit: ElementLimit
    deleted: DeletedAccountsData
    deletedLimit: ElementLimit
    nextService: ServiceIndex
    staging: ValidatorStateSnapshot
    queues: AuthorizationSnapshot
    privileges: PrivilegeSnapshot
    output: YieldValue
    provisions: ProvisionSetData
    transfers: TransferSetData
  AccumulationEffectContext* = object ## Read-only acyclic context; copies retain a version independently of later effect operations.
    data: nil EffectData
  ## Private pair retains exact initial provenance; neither child refers back to this owner or older pairs.
  PairData = ref object
    source: PreparedAccumulationContexts
    regular, exceptional: AccumulationEffectContext
  AccumulationEffects* = object ## Only prepared initial contexts create a pair; mutations preserve their service/input identity.
    data: nil PairData
  # Acyclic immutable plan retains its exact source pair and copied prospective debit/transfer.
  TransferPlanData = ref object
    source: AccumulationEffects
    metadata: ServiceMetadata
    transfer: DeferredTransfer
  PreparedAccumulationTransfer* = object ## Pure validated transfer; only commit can publish against this plan's retained source version.
    data: nil TransferPlanData
  AccumulationStorageChange* = object ## A completed storage mutation owns its successor pair and copied prior-value facts.
    effects*: AccumulationEffects ## Independently retained successor; prior regular/checkpoint owners remain unchanged.
    hadValue*: bool     ## Distinguish an absent key from a present value whose previous length was zero.
    previousBytes*: int ## Previous raw value length; meaningful only when hadValue is true.
  AccumulationServiceChange* = object ## A completed creation owns both its successor and the exact selected service ID.
    effects*: AccumulationEffects ## Current accounts and allocation cursor advance together; older versions remain valid.
    service*: ServiceIndex ## Reserved or automatic ID actually created by this operation.
  AccumulationEffectInfo* = object ## Copied current facts report retained outgoing transfers, provisions and service/cursor identity.
    service*: ServiceIndex ## The invoking service retains its initial identity.
    nextService*: ServiceIndex ## Current allocation cursor; historical initial provenance remains separate.
    transfers*, provisions*: int
    hasYield*: bool
    hasStaging*: bool ## A selected successful designate requires bounded original-delegator roster publication.
    hasPrivileges*: bool   ## A selected successful bless requires bounded manager-role/dictionary publication.
    hasAssignments*: bool  ## A selected successful assign requires bounded positional queue/assigner publication.
  AccumulationEffectResult*[T] = object ## Successful alternatives alone carry complete retained handles, facts or a present yield value.
    case status: AccumulationEffectError
    of None:
      completed: T # Contract-guarded extraction is the only public payload access.
    else:
      discard      # Refusals/defaults carry only their reason.

func error*[T](outcome: AccumulationEffectResult[T]): AccumulationEffectError =
  ## Inspect success/failure without permitting retagging or mutable access.
  outcome.status
func value*[T](outcome: AccumulationEffectResult[T]): T {.inline,
    requires: outcome.status == AccumulationEffectError.None.} =
  ## Extract selected success under compiler/runtime contracts, including optimized execution.
  outcome.completed

# Build an unpublished successor sharing frozen components; each operation replaces only its selected fields.
proc successorData(previous: EffectData, accounts: StateStoreSnapshot,
    selfMetadata = false, globalOnly = false): EffectData =
  var scope = previous.accountScope
  if not globalOnly and not sameStateSnapshot(previous.accounts, accounts):
    # Only explicit metadata operations certify self-only successors; unsupported ancestry is sticky.
    if selfMetadata and scope != AccumulationAccountScope.Unsupported:
      if scope notin {AccumulationAccountScope.SelfEntries,
          AccumulationAccountScope.CreatedAccounts, AccumulationAccountScope.DeletedAccounts}:
        scope = AccumulationAccountScope.SelfMetadata # Self metadata preserves any existing bounded self-key proof.
    else:
      scope = AccumulationAccountScope.Unsupported # No broader mutation can opt itself back into publication.
  EffectData(writeFacts: previous.writeFacts, writeFactLimit: previous.writeFactLimit,
    modified: previous.modified, modifiedLimit: previous.modifiedLimit,
    deleted: previous.deleted, deletedLimit: previous.deletedLimit,
    created: previous.created, createdLimit: previous.createdLimit,
    accountKeys: previous.accountKeys, accountKeyLimit: previous.accountKeyLimit,
    accountScope: scope, designated: previous.designated, blessed: previous.blessed,
    assigned: previous.assigned,
    initial: previous.initial, accounts: accounts,
    nextService: previous.nextService,
    staging: previous.staging, queues: previous.queues, privileges: previous.privileges,
    output: previous.output, provisions: previous.provisions, transfers: previous.transfers)

# Bound unique nonmetadata keys before allocating a trace or hashing its prospective map.
proc prepareSelfAccountKeys(previous: EffectData, writes: openArray[StateWrite]):
    AccumulationEffectResult[AccountKeysData] =
  if previous.accountScope == AccumulationAccountScope.Unsupported or uint64(
      previous.accountKeyLimit) == 0:
    return AccumulationEffectResult[AccountKeysData](status: AccumulationEffectError.None,
      completed: previous.accountKeys) # Disabled tracing and unsupported ancestry retain the existing execution behavior.
  let own = chapterServiceKey(StateChapter(255), previous.initial.contextInfo.value.service)
  let retained = previous.accountKeys
  var count = retained.keys.len
  for index, write in writes:
    # Self metadata is already handled by the batch's separate fixed-record policy.
    if array[31, byte](write.key) == array[31, byte](own): continue
    var seen = false
    for key in retained.keys:
      if array[31, byte](key) == array[31, byte](write.key): seen = true # Existing touched keys need no new descriptor.
    for earlier in 0..<index:
      if array[31, byte](writes[earlier].key) == array[31, byte](
          write.key): seen = true # Collapse duplicates within this atomic operation.
    if not seen:
      if uint64(count) >= uint64(previous.accountKeyLimit) or count >= high(int) div sizeof(StateKey):
        return AccumulationEffectResult[AccountKeysData](
            status: AccumulationEffectError.LimitExceeded) # No candidate map or partially copied proof.
      inc count
  if count == retained.keys.len:
    return AccumulationEffectResult[AccountKeysData](status: AccumulationEffectError.None,
      completed: previous.accountKeys) # Replacements/deletions of already touched keys share the immutable key set.
  var keys = newSeq[StateKey](count)
  var destination = 0
  for key in retained.keys:
    keys[destination] = key
    inc destination # The full new descriptor extent was preflighted above.
  for write in writes:
    if array[31, byte](write.key) == array[31, byte](
        own): continue # Fixed self metadata is never duplicated in the key trace.
    var seen = false
    for index in 0..<destination:
      if array[31, byte](keys[index]) == array[31, byte](
          write.key): seen = true # Preserve first-touch order without copying values.
    if not seen:
      keys[destination] = write.key
      inc destination
  AccumulationEffectResult[AccountKeysData](status: AccumulationEffectError.None,
    completed: AccountKeysData(keys: keys))

# Prepare the entire unique membership extension before publishing any associated account write.
proc prepareModifiedAccounts(previous: EffectData, additions: openArray[ServiceIndex]):
    AccumulationEffectResult[ModifiedAccountsData] =
  if uint64(previous.modifiedLimit) == 0:
    return AccumulationEffectResult[ModifiedAccountsData](status: AccumulationEffectError.None,
        completed: previous.modified) # Disabled tracking preserves earlier local execution behavior.
  let retained = previous.modified.values
  var count = retained.len
  for index, service in additions:
    var seen = false
    for value in retained:
      if uint32(value) == uint32(service): seen = true # Existing membership needs no additional capacity.
    for earlier in 0..<index:
      if uint32(additions[earlier]) == uint32(service): seen = true # Same-account direct transfers add one fact.
    if not seen:
      if uint64(count) >= uint64(previous.modifiedLimit) or count >= high(int) div sizeof(ServiceIndex):
        return AccumulationEffectResult[ModifiedAccountsData](
            status: AccumulationEffectError.LimitExceeded) # No partial set or candidate accounts escape.
      inc count
  if count == retained.len:
    return AccumulationEffectResult[ModifiedAccountsData](status: AccumulationEffectError.None,
        completed: previous.modified) # A repeated successful touch preserves exact immutable membership.
  var values = newSeq[ServiceIndex](count)
  var cursor = 0
  for service in retained:
    values[cursor] = service
    inc cursor # Retain deterministic first-touch order without parent context links.
  for service in additions:
    var seen = false
    for index in 0..<cursor:
      if uint32(values[index]) == uint32(service): seen = true # Collapse membership across both immutable inputs.
    if not seen:
      values[cursor] = service
      inc cursor
  AccumulationEffectResult[ModifiedAccountsData](status: AccumulationEffectError.None,
      completed: ModifiedAccountsData(values: values))

# Bound and copy unique account/key pairs before any associated candidate map can be published.
proc prepareAccountWriteFacts(previous: EffectData, additions: openArray[
    AccumulationAccountWriteFact]):
    AccumulationEffectResult[AccountWriteFactsData] =
  if uint64(previous.writeFactLimit) == 0:
    return AccumulationEffectResult[AccountWriteFactsData](status: AccumulationEffectError.None,
        completed: previous.writeFacts) # Disabled capture preserves earlier execution behavior.
  let retained = previous.writeFacts.values
  var count = retained.len
  for index, fact in additions:
    var seen = false
    for value in retained:
      if uint32(value.service) == uint32(fact.service) and array[31, byte](value.key) == array[31,
          byte](fact.key):
        seen = true # Repeated/restored writes retain one fixed owner/key fact.
    for earlier in 0..<index:
      if uint32(additions[earlier].service) == uint32(fact.service) and array[31, byte](additions[
          earlier].key) == array[31, byte](fact.key):
        seen = true # Collapse duplicates within one atomic operation too.
    if not seen:
      if uint64(count) >= uint64(previous.writeFactLimit) or count >= high(int) div sizeof(AccumulationAccountWriteFact):
        return AccumulationEffectResult[AccountWriteFactsData](
            status: AccumulationEffectError.LimitExceeded) # No partial facts or candidate accounts escape.
      inc count
  if count == retained.len:
    return AccumulationEffectResult[AccountWriteFactsData](status: AccumulationEffectError.None,
        completed: previous.writeFacts) # Unchanged membership shares its frozen backing.
  var values = newSeq[AccumulationAccountWriteFact](count)
  var cursor = 0
  for fact in retained:
    values[cursor] = fact
    inc cursor # Preserve successful first-touch order without parent links.
  for fact in additions:
    var seen = false
    for index in 0..<cursor:
      let value = values[index]
      if uint32(value.service) == uint32(fact.service) and array[31, byte](value.key) == array[31,
          byte](fact.key):
        seen = true # Distinct owners of one key remain visible for later collision rejection.
    if not seen:
      values[cursor] = fact
      inc cursor
  AccumulationEffectResult[AccountWriteFactsData](status: AccumulationEffectError.None,
      completed: AccountWriteFactsData(values: values))

proc prepareAccountWriteFacts(previous: EffectData, service: ServiceIndex, writes: openArray[StateWrite]):
    AccumulationEffectResult[AccountWriteFactsData] =
  if uint64(previous.writeFactLimit) == 0:
    return AccumulationEffectResult[AccountWriteFactsData](status: AccumulationEffectError.None,
        completed: previous.writeFacts) # Avoid descriptor allocation when capture is disabled.
  if writes.len > high(int) div sizeof(AccumulationAccountWriteFact):
    return AccumulationEffectResult[AccountWriteFactsData](
        status: AccumulationEffectError.LimitExceeded) # Prove the bounded typed extent before allocation.
  var facts = newSeq[AccumulationAccountWriteFact](writes.len)
  for index, write in writes:
    facts[index] = AccumulationAccountWriteFact(service: service,
        key: write.key) # Values stay in the account map, not in this fixed proof.
  prepareAccountWriteFacts(previous, facts)

# Bind the prepared self-key proof only after the same operation's account writes fully succeed.
proc selfAccountData(previous: EffectData, accounts: StateStoreSnapshot,
    keys: AccountKeysData): EffectData =
  result = successorData(previous, accounts)
  if previous.accountScope != AccumulationAccountScope.Unsupported and uint64(
      previous.accountKeyLimit) != 0:
    result.accountScope = if previous.accountScope in {AccumulationAccountScope.CreatedAccounts,
        AccumulationAccountScope.DeletedAccounts}:
      previous.accountScope else: AccumulationAccountScope.SelfEntries # Self writers preserve existing membership proofs.
    result.accountKeys = keys

# Bound fixed creation provenance before any candidate account map is hashed or published.
proc prepareCreatedAccount(previous: EffectData, service: ServiceIndex, requestKey: StateKey):
    AccumulationEffectResult[CreatedAccountsData] =
  if uint64(previous.createdLimit) == 0:
    return AccumulationEffectResult[CreatedAccountsData](status: AccumulationEffectError.None,
      completed: previous.created) # Disabled tracing never changes local new-call success; enabled facts survive unrelated scope gates.
  let count = previous.created.values.len
  if uint64(count) >= uint64(previous.createdLimit) or count >= high(int) div sizeof(AccumulationCreatedAccount):
    return AccumulationEffectResult[CreatedAccountsData](
        status: AccumulationEffectError.LimitExceeded) # No partial child/cursor/debit or descriptor allocation.
  var values = newSeq[AccumulationCreatedAccount](count+1)
  for index, value in previous.created.values:
    values[index] = value # Immutable fixed facts are copied without retaining parent effect chains.
  values[count] = AccumulationCreatedAccount(service: service, requestKey: requestKey)
  AccumulationEffectResult[CreatedAccountsData](status: AccumulationEffectError.None,
    completed: CreatedAccountsData(values: values))

# Bound successful-ejection membership before allocating proof storage or hashing the candidate map.
proc prepareDeletedAccount(previous: EffectData, service: ServiceIndex):
    AccumulationEffectResult[DeletedAccountsData] =
  if previous.accountScope == AccumulationAccountScope.Unsupported or uint64(
      previous.deletedLimit) == 0:
    return AccumulationEffectResult[DeletedAccountsData](status: AccumulationEffectError.None,
      completed: previous.deleted) # Disabled tracing retains the earlier local ejection behavior.
  let count = previous.deleted.values.len
  if uint64(count) >= uint64(previous.deletedLimit) or count >= high(int) div sizeof(AccumulationDeletedAccount):
    return AccumulationEffectResult[DeletedAccountsData](
        status: AccumulationEffectError.LimitExceeded) # No candidate balance or partial key owner escapes.
  var values = newSeq[AccumulationDeletedAccount](count+1)
  for index, value in previous.deleted.values:
    values[index] = value # Fixed service identities do not retain a chain of old effect versions.
  values[count] = AccumulationDeletedAccount(service: service)
  AccumulationEffectResult[DeletedAccountsData](status: AccumulationEffectError.None,
    completed: DeletedAccountsData(values: values))

proc effectInitialContext*(context: AccumulationEffectContext): AccumulationEffectResult[
    InitialAccumulationContext] =
  ## Retain immutable initial roles, next-ID and input provenance; current accounts use effectAccounts.
  let data = context.data
  if data == nil:
    # A default effect cannot supply another context as a substitute source.
    return AccumulationEffectResult[InitialAccumulationContext](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[InitialAccumulationContext](status: AccumulationEffectError.None,
    completed: data.initial)

proc effectAccounts*(context: AccumulationEffectContext): AccumulationEffectResult[
    StateStoreSnapshot] =
  ## Retain this exact version's current complete account map, independently of initial provenance.
  if context.data == nil:
    return AccumulationEffectResult[StateStoreSnapshot](status:
      AccumulationEffectError.Uninitialized) # No default owner grants a fabricated map.
  AccumulationEffectResult[StateStoreSnapshot](status: AccumulationEffectError.None,
    completed: context.data.accounts)

proc effectAccountScope*(context: AccumulationEffectContext): AccumulationEffectResult[
    AccumulationAccountScope] =
  ## Read this immutable lineage's proven account-change scope; defaults carry no successful classification.
  ## This observation cannot replace the batch's exact input/prior ownership or terminal selection proofs.
  if context.data == nil:
    return AccumulationEffectResult[AccumulationAccountScope](
      status: AccumulationEffectError.Uninitialized) # A default is not an untouched initialized context.
  AccumulationEffectResult[AccumulationAccountScope](status: AccumulationEffectError.None,
    completed: context.data.accountScope)

proc effectModifiedAccountCount*(context: AccumulationEffectContext): AccumulationEffectResult[int] =
  ## Count exact successful modified-account identities, including no-op/restored writes and incoming transfers.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[int](status: AccumulationEffectError.Uninitialized) # No default invocation facts.
  if uint64(data.modifiedLimit) == 0:
    return AccumulationEffectResult[int](status: AccumulationEffectError.ModifiedAccountsDisabled) # Disabled is distinct from an enabled empty set.
  AccumulationEffectResult[int](status: AccumulationEffectError.None,
      completed: data.modified.values.len)

proc effectModifiedAccountAt*(context: AccumulationEffectContext,
    index: AccumulationModifiedAccountIndex): AccumulationEffectResult[ServiceIndex] =
  ## Copy one first-touch-ordered member; no mutable membership storage is exported.
  let count = context.effectModifiedAccountCount
  if count.error != AccumulationEffectError.None:
    return AccumulationEffectResult[ServiceIndex](
        status: count.error) # Defaults/disabled tracking never expose a synthetic identity.
  if uint64(index) >= uint64(count.value):
    return AccumulationEffectResult[ServiceIndex](
        status: AccumulationEffectError.InvalidIndex) # Bound before native narrowing.
  let data = context.data
  assert data != nil # Successful count retains this initialized owner.
  AccumulationEffectResult[ServiceIndex](status: AccumulationEffectError.None,
      completed: data.modified.values[int(uint64(index))])

proc effectAccountModified*(context: AccumulationEffectContext,
    service: ServiceIndex): AccumulationEffectResult[bool] =
  ## Query successful membership without treating equal final bytes as absence of modification.
  let count = context.effectModifiedAccountCount
  if count.error != AccumulationEffectError.None:
    return AccumulationEffectResult[bool](status: count.error) # No fabricated false result for absent tracking.
  let data = context.data
  assert data != nil # Successful count retains this initialized owner.
  for value in data.modified.values:
    if uint32(value) == uint32(service):
      return AccumulationEffectResult[bool](status: AccumulationEffectError.None,
          completed: true) # Exact nominal identity membership.
  AccumulationEffectResult[bool](status: AccumulationEffectError.None, completed: false)

proc effectAccountWriteFactCount*(context: AccumulationEffectContext): AccumulationEffectResult[int] =
  ## Count unique successful account/key facts independently of final root or value equality.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[int](status: AccumulationEffectError.Uninitialized) # Defaults expose no facts.
  if uint64(data.writeFactLimit) == 0:
    return AccumulationEffectResult[int](status: AccumulationEffectError.AccountWriteFactsDisabled) # Disabled capture is not a proven empty set.
  AccumulationEffectResult[int](status: AccumulationEffectError.None,
      completed: data.writeFacts.values.len)

proc effectAccountWriteFactAt*(context: AccumulationEffectContext,
    index: AccumulationAccountWriteFactIndex): AccumulationEffectResult[
        AccumulationAccountWriteFact] =
  ## Copy one fact from this exact immutable context; no mutable backing or detached value escapes.
  let count = context.effectAccountWriteFactCount
  if count.error != AccumulationEffectError.None:
    return AccumulationEffectResult[AccumulationAccountWriteFact](
        status: count.error) # Default/disabled capture cannot fabricate an account/key pair.
  if uint64(index) >= uint64(count.value):
    return AccumulationEffectResult[AccumulationAccountWriteFact](
        status: AccumulationEffectError.InvalidIndex) # Bound before native narrowing.
  let data = context.data
  assert data != nil # Successful count retains this initialized owner.
  AccumulationEffectResult[AccumulationAccountWriteFact](status: AccumulationEffectError.None,
      completed: data.writeFacts.values[int(uint64(index))])

proc effectAccountWriteCount*(context: AccumulationEffectContext): AccumulationEffectResult[int] =
  ## Count immutable traced self keys; unsupported lineages expose no incomplete publication proof.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[int](status: AccumulationEffectError.Uninitialized) # Defaults cannot authorize zero work.
  if data.accountScope == AccumulationAccountScope.Unsupported:
    return AccumulationEffectResult[int](status: AccumulationEffectError.InvalidState) # A partial trace cannot certify a broader mutation.
  AccumulationEffectResult[int](status: AccumulationEffectError.None,
      completed: data.accountKeys.keys.len)

proc effectAccountWriteKeyAt*(context: AccumulationEffectContext,
    index: AccumulationAccountWriteIndex):
    AccumulationEffectResult[StateKey] =
  ## Copy one key bound to this retained context; resolve its final value only in the same context's effectAccounts.
  let count = context.effectAccountWriteCount
  if count.error != AccumulationEffectError.None:
    return AccumulationEffectResult[StateKey](status: count.error) # Preserve default/unsupported proof refusal.
  if uint64(index) >= uint64(count.value):
    return AccumulationEffectResult[StateKey](status: AccumulationEffectError.InvalidIndex) # Check the full-width ordinal before narrowing.
  let data = context.data
  assert data != nil # Successful count proves this retained immutable owner is initialized.
  AccumulationEffectResult[StateKey](status: AccumulationEffectError.None,
    completed: data.accountKeys.keys[int(uint64(index))])

proc effectCreatedAccountFactCount*(context: AccumulationEffectContext): AccumulationEffectResult[int] =
  ## Read complete enabled creation membership independently of legacy account publication scope.
  ## Every successful new call captures its fact before hashing, even after an unrelated unsupported mutation.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[int](status: AccumulationEffectError.Uninitialized) # Default is not enabled empty tracing.
  if uint64(data.createdLimit) == 0:
    return AccumulationEffectResult[int](status: AccumulationEffectError.CreatedAccountsDisabled) # Explicitly distinguish disabled history from zero creations.
  AccumulationEffectResult[int](status: AccumulationEffectError.None,
      completed: data.created.values.len)

proc effectCreatedAccountFactAt*(context: AccumulationEffectContext,
    index: AccumulationCreatedAccountIndex): AccumulationEffectResult[AccumulationCreatedAccount] =
  ## Copy genuine fixed creation provenance through the same enabled owner; account values remain in effectAccounts.
  let count = context.effectCreatedAccountFactCount
  if count.error != AccumulationEffectError.None:
    return AccumulationEffectResult[AccumulationCreatedAccount](
        status: count.error) # No partial or disabled proof extraction.
  if uint64(index) >= uint64(count.value):
    return AccumulationEffectResult[AccumulationCreatedAccount](
        status: AccumulationEffectError.InvalidIndex) # Check upper bits before native narrowing.
  let data = context.data
  assert data != nil # The successful count validated this exact immutable owner.
  AccumulationEffectResult[AccumulationCreatedAccount](status: AccumulationEffectError.None,
    completed: data.created.values[int(uint64(index))])

proc effectCreatedAccountCount*(context: AccumulationEffectContext): AccumulationEffectResult[int] =
  ## Count this selected context's genuine creations; unsupported lineages expose no partial membership proof.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[int](status: AccumulationEffectError.Uninitialized) # A default is not an initialized empty creation set.
  if data.accountScope == AccumulationAccountScope.Unsupported:
    return AccumulationEffectResult[int](status: AccumulationEffectError.InvalidState) # Broader account changes cannot masquerade as a complete trace.
  AccumulationEffectResult[int](status: AccumulationEffectError.None,
      completed: data.created.values.len)

proc effectCreatedAccountAt*(context: AccumulationEffectContext,
    index: AccumulationCreatedAccountIndex):
    AccumulationEffectResult[AccumulationCreatedAccount] =
  ## Copy fixed creation facts at a full-width ordinal; obtain values from this same context's effectAccounts only.
  let count = context.effectCreatedAccountCount
  if count.error != AccumulationEffectError.None:
    return AccumulationEffectResult[AccumulationCreatedAccount](
        status: count.error) # No uninitialized or incomplete proof payload.
  if uint64(index) >= uint64(count.value):
    return AccumulationEffectResult[AccumulationCreatedAccount](
        status: AccumulationEffectError.InvalidIndex) # Bound before narrowing.
  let data = context.data
  assert data != nil # Successful count established the retained immutable owner.
  AccumulationEffectResult[AccumulationCreatedAccount](status: AccumulationEffectError.None,
    completed: data.created.values[int(uint64(index))])

proc effectDeletedAccountCount*(context: AccumulationEffectContext): AccumulationEffectResult[int] =
  ## Count the selected context's genuine ejections; unsupported lineages expose no incomplete membership proof.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[int](status: AccumulationEffectError.Uninitialized) # A default is not an initialized empty deletion set.
  if data.accountScope == AccumulationAccountScope.Unsupported:
    return AccumulationEffectResult[int](status: AccumulationEffectError.InvalidState) # Broader effects cannot impersonate a complete deletion trace.
  AccumulationEffectResult[int](status: AccumulationEffectError.None,
      completed: data.deleted.values.len)

proc effectDeletedAccountAt*(context: AccumulationEffectContext,
    index: AccumulationDeletedAccountIndex):
    AccumulationEffectResult[AccumulationDeletedAccount] =
  ## Copy one fixed deletion fact at a full-width ordinal, bound to this retained account context.
  let count = context.effectDeletedAccountCount
  if count.error != AccumulationEffectError.None:
    return AccumulationEffectResult[AccumulationDeletedAccount](
        status: count.error) # Defaults/unsupported traces expose no payload.
  if uint64(index) >= uint64(count.value):
    return AccumulationEffectResult[AccumulationDeletedAccount](
        status: AccumulationEffectError.InvalidIndex) # Prove the native index before narrowing.
  let data = context.data
  assert data != nil # Successful count proves this immutable owner is initialized.
  AccumulationEffectResult[AccumulationDeletedAccount](status: AccumulationEffectError.None,
    completed: data.deleted.values[int(uint64(index))])

proc effectPrivileges*(context: AccumulationEffectContext): AccumulationEffectResult[
    PrivilegeSnapshot] =
  ## Retain this version's exact current roles and allowances, independently of historical initial privileges.
  if context.data == nil:
    return AccumulationEffectResult[PrivilegeSnapshot](status:
      AccumulationEffectError.Uninitialized) # No fabricated default manager or empty dictionary.
  AccumulationEffectResult[PrivilegeSnapshot](status: AccumulationEffectError.None,
    completed: context.data.privileges)

proc effectQueues*(context: AccumulationEffectContext): AccumulationEffectResult[
    AuthorizationSnapshot] =
  ## Retain this exact version's ordered queues; initial provenance remains independently available.
  if context.data == nil:
    return AccumulationEffectResult[AuthorizationSnapshot](
        status: AccumulationEffectError.Uninitialized) # Defaults grant no queue owner.
  AccumulationEffectResult[AuthorizationSnapshot](status: AccumulationEffectError.None,
    completed: context.data.queues)

proc effectStaging*(context: AccumulationEffectContext): AccumulationEffectResult[
    ValidatorStateSnapshot] =
  ## Retain this version's exact ordered staging roster independently of initial population and later effects.
  if context.data == nil:
    return AccumulationEffectResult[ValidatorStateSnapshot](
        status: AccumulationEffectError.Uninitialized) # Defaults grant no staging owner.
  AccumulationEffectResult[ValidatorStateSnapshot](status: AccumulationEffectError.None,
    completed: context.data.staging)

proc effectInfo*(context: AccumulationEffectContext): AccumulationEffectResult[
    AccumulationEffectInfo] =
  ## Copy current yield-presence and retained service facts, never mutable implication storage.
  let data = context.data
  if data == nil:
    # Missing owners cannot masquerade as valid services with zero effects.
    return AccumulationEffectResult[AccumulationEffectInfo](
        status: AccumulationEffectError.Uninitialized)
  let source = data.initial.contextInfo.value
  AccumulationEffectResult[AccumulationEffectInfo](status: AccumulationEffectError.None,
    completed: AccumulationEffectInfo(service: source.service, nextService: data.nextService,
      hasStaging: data.designated, hasPrivileges: data.blessed, hasAssignments: data.assigned,
      transfers: data.transfers.values.len, provisions: data.provisions.values.len,
      hasYield: data.output.present))

proc effectYield*(context: AccumulationEffectContext): AccumulationEffectResult[OutputCommitment] =
  ## Read a present yield by value; default and absent alternatives never return a fake zero commitment.
  let data = context.data
  if data == nil:
    # Default contexts have no selected yield state.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.Uninitialized)
  if not data.output.present:
    # A successfully prepared context may legitimately have no yield yet.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.YieldAbsent)
  AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.None,
    completed: data.output.commitment)

proc effectContext*(effects: AccumulationEffects, dimension: AccumulationDimension):
    AccumulationEffectResult[AccumulationEffectContext] =
  ## Select one exact version; invalid enum casts cannot silently alias the exceptional dimension.
  if ord(dimension) < ord(AccumulationDimension.Regular) or ord(dimension) > ord(
      AccumulationDimension.Exceptional):
    # Reject unsupported dimensions before selecting any retained child.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.InvalidDimension)
  let data = effects.data
  if data == nil:
    # Default pairs are not initialized I squared values.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.Uninitialized)
  let selected = if dimension == AccumulationDimension.Regular: data.regular
    else: data.exceptional # Only the two validated dimensions remain.
  AccumulationEffectResult[AccumulationEffectContext](status: AccumulationEffectError.None,
    completed: selected)

proc effectsSource*(effects: AccumulationEffects): AccumulationEffectResult[
    PreparedAccumulationContexts] =
  ## Retain original prepared provenance independently of effect versions and checkpoint lifetimes.
  let data = effects.data
  if data == nil:
    # No default pair may grant an initialized preparation certificate.
    return AccumulationEffectResult[PreparedAccumulationContexts](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[PreparedAccumulationContexts](status: AccumulationEffectError.None,
    completed: data.source)

proc prepareAccumulationEffects*(contexts: PreparedAccumulationContexts,
    accountWriteKeys = ElementLimit(0), createdAccounts = ElementLimit(0),
        deletedAccounts = ElementLimit(0), modifiedAccounts = ElementLimit(0),
            accountWriteFacts = ElementLimit(0)): AccumulationEffectResult[
    AccumulationEffects] =
  ## Begin at the actual initial I in both dimensions; no caller-selected replacement state or yield is accepted.
  ## accountWriteFacts independently bounds exact successful service/key pairs; zero disables their queries.
  ## modifiedAccounts enables exact unique membership; zero disables those queries without changing earlier execution.
  ## accountWriteKeys bounds self keys; createdAccounts/deletedAccounts independently bound membership facts. Zero retains the earlier gates.
  let initial = contexts.initialContext(AccumulationDimension.Regular)
  if initial.error != AccumulationContextError.None:
    # Only successfully prepared immutable contexts can authorize host state effects.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.InvalidContexts)
  var facts: seq[AccumulationAccountWriteFact] = @[]
  var members: seq[ServiceIndex] = @[]
  if uint64(modifiedAccounts) != 0 or uint64(accountWriteFacts) != 0:
    let received = initial.value.contextInvocation.value.bootstrapService.value.serviceInfo.value.transfers
    if received != 0:
      let service = initial.value.contextInfo.value.service
      if uint64(modifiedAccounts) != 0:
        members.add(service) # Even a zero-valued incoming transfer marks the recipient.
      if uint64(accountWriteFacts) != 0:
        facts.add(AccumulationAccountWriteFact(service: service, key: chapterServiceKey(
            StateChapter(255), service))) # Initial credit belongs to the exact producing invocation too.
  let current = AccumulationEffectContext(data: EffectData(initial: initial.value,
    accounts: initial.value.contextAccounts.value, accountScope: AccumulationAccountScope.Initial,
    designated: false, blessed: false, assigned: false,
    modified: ModifiedAccountsData(values: members), modifiedLimit: modifiedAccounts,
    writeFacts: AccountWriteFactsData(values: facts), writeFactLimit: accountWriteFacts,
    accountKeys: AccountKeysData(keys: @[]), accountKeyLimit: accountWriteKeys,
    created: CreatedAccountsData(values: @[]), createdLimit: createdAccounts,
    deleted: DeletedAccountsData(values: @[]), deletedLimit: deletedAccounts,
    nextService: initial.value.contextInfo.value.nextService,
    staging: initial.value.contextStaging.value, queues: initial.value.contextQueues.value,
    privileges: initial.value.contextPrivileges.value,
    output: YieldValue(present: false), transfers: TransferSetData(values: @[]),

provisions: ProvisionSetData(values: @[], bytes: 0, largest: 0)))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: contexts, regular: current,
        exceptional: current)))

proc recordAccumulationYield*(effects: AccumulationEffects, commitment: OutputCommitment):
    AccumulationEffectResult[AccumulationEffects] =
  ## Apply only the state part of a validated yield call: replace regular yield, preserving the checkpoint.
  ## The host dispatcher must first charge gas/read guest memory; failures there must not call this operation.
  let data = effects.data
  if data == nil:
    # Refuse before constructing a partially initialized regular context.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  let previous = data.regular.data
  assert previous != nil # Private construction preserves initialized children for every published pair.
  let candidate = successorData(previous, previous.accounts)
  candidate.output = YieldValue(present: true, commitment: commitment)
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc checkpointAccumulationEffects*(effects: AccumulationEffects): AccumulationEffectResult[
    AccumulationEffects] =
  ## Apply only checkpoint's implication assignment Y'=X; later regular changes cannot alter the retained snapshot.
  ## Guest gas/r7 handling is outside this state-only operation; no implicit checkpoint occurs on yield.
  let data = effects.data
  if data == nil:
    # A checkpoint cannot turn an uninitialized pair into successful empty implications.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: data.regular,
      exceptional: data.regular)))

proc effectProvisionAt*(context: AccumulationEffectContext, index: AccumulationProvisionIndex):
    AccumulationEffectResult[AccumulationProvision] =
  ## Retain one provision only after checking its ordinal against this exact immutable context.
  let data = context.data
  if data == nil:
    # Default contexts contain no validated provision sequence.
    return AccumulationEffectResult[AccumulationProvision](
        status: AccumulationEffectError.Uninitialized)
  if uint64(index) >= uint64(data.provisions.values.len):
    # Prove the full-width ordinal before narrowing or accessing the retained sequence.
    return AccumulationEffectResult[AccumulationProvision](
        status: AccumulationEffectError.InvalidIndex)
  AccumulationEffectResult[AccumulationProvision](status: AccumulationEffectError.None,
    completed: data.provisions.values[int(uint64(index))])

proc provisionInfo*(provision: AccumulationProvision): AccumulationEffectResult[
    AccumulationProvisionInfo] =
  ## Copy the exact target and length from one owner-bound provision; default handles are not empty blobs.
  let data = provision.data
  if data == nil:
    # A default provision cannot fabricate target zero or a valid zero-byte payload.
    return AccumulationEffectResult[AccumulationProvisionInfo](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[AccumulationProvisionInfo](status: AccumulationEffectError.None,
    completed: AccumulationProvisionInfo(service: data.service, bytes: data.bytes.len))

proc copyProvisionBytes*(provision: AccumulationProvision): AccumulationEffectResult[seq[byte]] =
  ## Return independent bytes from the retained provision; caller mutations never affect later extraction/checkpoints.
  let data = provision.data
  if data == nil:
    # Empty successful payloads require an actual validated owner.
    return AccumulationEffectResult[seq[byte]](status: AccumulationEffectError.Uninitialized)
  var bytes = newSeq[byte](data.bytes.len)
  # Exact retained length was bounded before construction; copy without exporting shared mutable storage.
  for i, octet in data.bytes: bytes[i] = octet
  AccumulationEffectResult[seq[byte]](status: AccumulationEffectError.None, completed: bytes)

proc recordAccumulationProvision*(effects: AccumulationEffects, service: ServiceIndex,
    bytes: openArray[byte], limits: AccumulationProvisionLimits): AccumulationEffectResult[
        AccumulationEffects] =
  ## Retain a requested target/blob pair in regular implications only, with WHO/HUH-style protocol refusals.
  ## Stable bytes are borrowed during the call; accepted bytes are independently owned. Guest gas/memory checks precede this API.
  ## All refusals preserve the caller's pair and expose no partially captured provision.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # No default pair authorizes account lookup or retained bytes.
  let previous = data.regular.data
  assert previous != nil # Only private constructors publish initialized children.
  let size = uint64(bytes.len)
  if size >= uint64(high(uint32))-1:
    fail(AccumulationEffectError.InvalidLength) # Current request lengths exclude both reserved namespace prefixes.
  if size > uint64(limits.perBlob) or previous.provisions.largest > uint64(limits.perBlob) or
      previous.provisions.bytes > uint64(limits.totalBlobBytes) or
      uint64(previous.provisions.values.len) > uint64(limits.items):
    fail(AccumulationEffectError.LimitExceeded) # Bound hash/scan work and validate retained-prefix policy before new work.
  let state = previous.accounts
  let account = state.lookup(chapterServiceKey(StateChapter(255), service))
  if account.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Orphan request records do not create a target account.
  if account.error != StateStoreError.None:
    fail(AccumulationEffectError.InvalidState) # Default/corrupt backing cannot fabricate WHO or HUH.
  let digest = blake2b256(bytes)
  if digest.error != CryptoError.None:
    fail(AccumulationEffectError.BackendFailure) # No failed hash becomes an unrequested verdict.
  let requested = preimageRequested(state, service, ServicePreimageHash(array[32, byte](
      digest.value)),
    RequestLength(uint32(size)))
  if requested.error == PreimageTransitionError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Preserve canonical namespace failures separately.
  if requested.error == PreimageTransitionError.MalformedState:
    fail(AccumulationEffectError.MalformedState) # Never normalize malformed account/history bytes into ordinary HUH.
  if requested.error != PreimageTransitionError.None:
    fail(AccumulationEffectError.InvalidState) # Only a complete canonical query can authorize provision capture.
  if not requested.value:
    fail(AccumulationEffectError.NotRequested) # Only the exact outstanding (hash,length) request is eligible.
  # Equality is target plus complete raw bytes, not hash-only equality or an unrelated owner's coordinates.
  for provision in previous.provisions.values:
    let retained = provision.data
    assert retained != nil # Published provision sequences contain initialized owners only.
    if uint32(retained.service) == uint32(service) and retained.bytes == bytes:
      fail(AccumulationEffectError.AlreadyProvided) # Duplicate refusal requires no additional record capacity.
  if uint64(previous.provisions.values.len) >= uint64(limits.items) or
      previous.provisions.values.len >= high(int) div sizeof(AccumulationProvision) or
      size > uint64(limits.totalBlobBytes)-previous.provisions.bytes:
    fail(AccumulationEffectError.LimitExceeded) # Prove count/native extent and aggregate addition before allocation.
  var owned = newSeq[byte](bytes.len)
  # Borrowed caller bytes become immutable private storage before any successful pair is published.
  for i, octet in bytes: owned[i] = octet
  var provisions = newSeq[AccumulationProvision](previous.provisions.values.len+1)
  # Share only immutable prior provision owners; no new version links back to its parent effect pair.
  for i, provision in previous.provisions.values: provisions[i] = provision
  provisions[previous.provisions.values.len] = AccumulationProvision(data: ProvisionData(
      service: service, bytes: owned))
  let candidate = successorData(previous, previous.accounts)
  candidate.provisions = ProvisionSetData(values: provisions,
    bytes: previous.provisions.bytes+size, largest: max(previous.provisions.largest, size))
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

## Subtract an exact 128-bit product from a budget of at most 2^65-2 tokens.
## Limb products and their carry sums are bounded before arithmetic; no saturation impersonates equality.
proc consumeDeposit(low, upper: var uint64, count, rate: uint64): bool =
  let mask = 0xffffffff'u64
  let p0 = (count and mask)*(rate and mask)
  let p1 = (count and mask)*(rate shr 32)
  let p2 = (count shr 32)*(rate and mask)
  let p3 = (count shr 32)*(rate shr 32)
  let middle = (p0 shr 32)+(p1 and mask)+(p2 and mask) # Below 3*2^32.
  let productLow = ((middle and mask) shl 32) or (p0 and mask)
  let productHigh = p3+(p1 shr 32)+(p2 shr 32)+(middle shr 32) # Exact high half of a uint64 product.
  if productHigh > upper or (productHigh == upper and productLow > low):
    return false # The mathematical deposit exceeds the remaining balance plus gratis.
  if productLow > low:
    upper = upper-productHigh-1 # Comparison proves the borrow exists.
    low = high(uint64)-productLow+low+1 # productLow>low proves no intermediate overflow.
  else:
    upper -= productHigh # No low-limb borrow.
    low -= productLow
  true

## Consume the same exact three deposit terms for both funding and minimum-balance queries.
proc consumeAccountDeposit(metadata: ServiceMetadata, parameters: Parameters,
    low, upper: var uint64): bool =
  for term in [(1'u64, parameters.get(depositPerAccount)),
      (uint64(metadata.storageItems), parameters.get(depositPerItem)),
      (uint64(metadata.storageBytes), parameters.get(depositPerByte))]:
    let (count, rate) = term # Each independent term consumes the remaining exact two-limb budget.
    if not consumeDeposit(low, upper, count, rate):
      return false # FULL includes products larger than the complete available budget.
  true

## Compare the deposit with both balance components plus gratis using a bounded two-limb sum.
## Three full-width terms need at most two carry bits; subtraction never narrows the protocol domains.
proc funded(metadata: ServiceMetadata, parameters: Parameters): bool =
  var low = 0'u64
  var upper = 0'u64
  for amount in [uint64(metadata.balance), uint64(metadata.supervisorBalance), uint64(
      metadata.depositOffset)]:
    if amount > high(uint64)-low:
      inc upper
      low = amount-(high(uint64)-low)-1 # Preserve the carry without forming an overflowing addition.
    else:
      low += amount # The preceding comparison proves the complete low-limb sum fits.
  consumeAccountDeposit(metadata, parameters, low, upper)

proc effectAccountInfo*(context: AccumulationEffectContext, service: ServiceIndex,
    parameters: Parameters): AccumulationEffectResult[array[AccumulationAccountInfoBytes, byte]] =
  ## Encode this version's complete account into the fixed Omega_I wire record.
  ## Refused/default queries contain only a reason; no caller-selected account or fabricated bytes escape.
  ## The fixed record includes computed minimum balance and has no metadata version byte.
  ## UnknownService, invalid parameters and unencodable/malformed fields remain explicit guarded failures.
  # Retain no partial record on invalid provenance, missing accounts or malformed dependent values.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[array[AccumulationAccountInfoBytes, byte]](status: reason)
  let data = context.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default versions cannot authorize account queries.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # No substituted default deposit configuration.
  let found = data.accounts.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Protocol NONE is selected only by a complete-map absence.
  if found.error != StateStoreError.None:
    fail(AccumulationEffectError.InvalidState) # Invalid owners cannot fabricate absent accounts.
  if found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Bound the entire metadata copy before allocation.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Require the one complete canonical version-zero schema.
  let metadata = decoded.value.metadata
  let gratis = uint64(metadata.depositOffset)
  var low = high(uint64)
  var upper = 0'u64
  if gratis != 0:
    upper = 1 # UINT64_MAX+gratis has this exact two-limb representation.
    low = gratis-1
  if not consumeAccountDeposit(metadata, parameters, low, upper):
    fail(AccumulationEffectError.MalformedState) # Deposit>UINT64_MAX+gratis implies an unencodable E8 threshold.
  # Remaining budget is UINT64_MAX+gratis-deposit; subtract from UINT64_MAX only when nonnegative.
  let minimum = (if upper != 0 or low == high(uint64): 0'u64 else: high(uint64)-low)
  var bytes = default(array[AccumulationAccountInfoBytes, byte])
  let hash = array[32, byte](metadata.codeHash)
  for i in 0..<32:
    bytes[i] = hash[i] # Raw hash has no version, count or prefix.
  for field, value in [uint32(metadata.supervisor), uint32(metadata.supervisorCreated)]:
    for i in 0..<4:
      bytes[32+field*4+i] = byte((value shr (8*i)) and 255) # Supervisor identity includes its creation slot.
  for field, value in [uint64(metadata.balance), uint64(metadata.supervisorBalance), minimum,
      uint64(metadata.minimumAccumulationGas), uint64(metadata.minimumTransferGas), uint64(
          metadata.storageBytes)]:
    for i in 0..<8:
      bytes[40+field*8+i] = byte((value shr (8*i)) and 255) # Six exact E8 values precede the item count.
  for i in 0..<4:
    bytes[88+i] = byte((uint32(metadata.storageItems) shr (8*i)) and 255) # Items use E4 before gratis.
  for i in 0..<8:
    bytes[92+i] = byte((gratis shr (8*i)) and 255) # Preserve all gratis bits after the E4 item field.
  for field, value in [uint32(metadata.created), uint32(metadata.lastAccumulation), uint32(
      metadata.parent)]:
    for i in 0..<4:
      bytes[100+field*4+i] = byte((value shr (8*i)) and 255) # Exact E4 slots and parent finish the record.
  AccumulationEffectResult[array[AccumulationAccountInfoBytes, byte]](
    status: AccumulationEffectError.None, completed: bytes)

# Decode one bounded current record without hashing or fabricating a missing participant.
proc currentAccountMetadata(accounts: StateStoreSnapshot, service: ServiceIndex):
    AccumulationEffectResult[ServiceMetadata] =
  let found = accounts.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error == StateStoreError.MissingKey:
    return AccumulationEffectResult[ServiceMetadata](
        status: AccumulationEffectError.UnknownService) # Existence precedes authority.
  if found.error != StateStoreError.None:
    return AccumulationEffectResult[ServiceMetadata](
        status: AccumulationEffectError.InvalidState) # Invalid snapshots cannot prove absence.
  if found.value.byteLength != ServiceMetadataBytes:
    return AccumulationEffectResult[ServiceMetadata](
        status: AccumulationEffectError.MalformedState) # Bound the canonical metadata copy first.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    return AccumulationEffectResult[ServiceMetadata](
        status: AccumulationEffectError.MalformedState) # No malformed identity may authorize reassignment.
  AccumulationEffectResult[ServiceMetadata](status: AccumulationEffectError.None,
      completed: decoded.value.metadata)

# Effective supervision binds the designated service incarnation; missing/recreated accounts fall back to self.
proc effectiveSupervisor(accounts: StateStoreSnapshot, service: ServiceIndex,
    metadata: ServiceMetadata): AccumulationEffectResult[ServiceIndex] =
  if uint32(metadata.supervisor) == uint32(service):
    return AccumulationEffectResult[ServiceIndex](status: AccumulationEffectError.None,
        completed: service) # Self designation and fallback select the same authority.
  let designated = currentAccountMetadata(accounts, metadata.supervisor)
  if designated.error == AccumulationEffectError.UnknownService:
    return AccumulationEffectResult[ServiceIndex](status: AccumulationEffectError.None,
        completed: service) # A missing designation grants no authority to a future account.
  if designated.error != AccumulationEffectError.None:
    return AccumulationEffectResult[ServiceIndex](
        status: designated.error) # Malformed backing is a local refusal, not a guessed fallback.
  let selected = if uint32(designated.value.created) == uint32(metadata.supervisorCreated):
    metadata.supervisor
  else:
    service # Reusing an ID with a different creation slot cannot inherit authority.
  AccumulationEffectResult[ServiceIndex](status: AccumulationEffectError.None, completed: selected)

# Non-privileged mutations admit the service itself or its current effective supervisor, before namespace work.
proc authorizedAccountMetadata(previous: EffectData,
    service: ServiceIndex): AccumulationEffectResult[ServiceMetadata] =
  let self = previous.initial.contextInfo.value.service
  let selected = currentAccountMetadata(previous.accounts, service)
  if selected.error != AccumulationEffectError.None:
    if selected.error == AccumulationEffectError.UnknownService and uint32(service) == uint32(self):
      return AccumulationEffectResult[ServiceMetadata](
          status: AccumulationEffectError.MalformedState) # Never reconstruct a missing current invoker.
    return AccumulationEffectResult[ServiceMetadata](
        status: selected.error) # A missing foreign account is protocol WHO.
  if uint32(service) != uint32(self):
    let authority = effectiveSupervisor(previous.accounts, service, selected.value)
    if authority.error != AccumulationEffectError.None:
      return AccumulationEffectResult[ServiceMetadata](
          status: authority.error) # Malformed provenance cannot grant authority.
    if uint32(authority.value) != uint32(self):
      return AccumulationEffectResult[ServiceMetadata](
          status: AccumulationEffectError.NotRequested) # HUH precedes history/storage hashing and funding.
  selected # Canonical fixed metadata is copied, with no retained borrow or mutable authority token.

proc recordAccumulationStorage*(effects: AccumulationEffects, key, value: openArray[byte],
    parameters: Parameters, limit: ByteLimit, target: ServiceIndex): AccumulationEffectResult[
        AccumulationStorageChange] =
  ## Apply one raw self/supervised storage mutation atomically, retaining initial provenance and checkpoint.
  ## UnknownService/NotRequested distinguish absent targets from unauthorized writes before namespace hashing.
  ## Borrowed bytes remain stable during this call; the complete-map store independently captures accepted values.
  ## Empty values delete the key. Success retains the successor and distinguishes absent/present-empty prior values.
  ## StorageFull is a funding refusal; copy/store limits, malformed counters and backend failure publish no successor.
  # Refuse without publishing a candidate map or successor effect pair.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationStorageChange](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default pairs cannot authorize mutations.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # No default deposit schedule is accepted.
  if uint64(key.len) > uint64(limit) or uint64(value.len) > uint64(limit):
    fail(AccumulationEffectError.LimitExceeded) # Bound both borrowed extents before hashing/allocation.
  let previous = data.regular.data
  assert previous != nil # Private constructors retain complete current account snapshots.
  let self = previous.initial.contextInfo.value.service
  let service = target
  let accountKey = chapterServiceKey(StateChapter(255), service)
  let selected = authorizedAccountMetadata(previous, service)
  if selected.error != AccumulationEffectError.None:
    fail(selected.error) # Canonical target and authority precede namespace hashing.
  var metadata = selected.value
  let derived = serviceStorageKey(service, key, limit)
  if derived.error != ServiceValueError.None:
    fail(AccumulationEffectError.BackendFailure) # No alternate namespace on failed hashing.
  let old = previous.accounts.lookup(derived.value)
  if old.error notin {StateStoreError.None, StateStoreError.MissingKey}:
    fail(AccumulationEffectError.InvalidState) # No fabricated absent value from an invalid map.
  let hadValue = old.error == StateStoreError.None
  let oldBytes = (if hadValue: old.value.byteLength else: 0)
  var items = uint64(metadata.storageItems)
  var octets = uint64(metadata.storageBytes)
  if hadValue:
    # Remove the old footprint before adding a replacement; bounded native key/value lengths fit uint64.
    if uint64(key.len) > high(uint64)-34-uint64(oldBytes):
      fail(AccumulationEffectError.InvalidState) # Prove footprint addition before forming it.
    let footprint = 34'u64+uint64(key.len)+uint64(oldBytes)
    if items == 0 or octets < footprint:
      fail(AccumulationEffectError.MalformedState) # Inconsistent stored counters never underflow.
    items -= 1
    octets -= footprint
  if value.len != 0:
    # A nonempty value inserts one item; an empty value deletes, including absent-key no-ops.
    if uint64(key.len) > high(uint64)-34-uint64(value.len):
      fail(AccumulationEffectError.InvalidState) # Full-width native extents cannot wrap a footprint.
    let footprint = 34'u64+uint64(key.len)+uint64(value.len)
    if items == uint64(high(uint32)) or footprint > high(uint64)-octets:
      fail(AccumulationEffectError.InvalidState) # Preserve declared E4/E8 footprint domains without wrapping.
    items += 1
    octets += footprint
  metadata.storageItems = AccountStorageItems(uint32(items))
  metadata.storageBytes = AccountStorageBytes(octets)
  if not funded(metadata, parameters):
    fail(AccumulationEffectError.StorageFull) # FULL preserves the original map even for an underfunded deletion.
  let encoded = serviceMetadataEntry(service, metadata, ByteLimit(ServiceMetadataBytes)).value
  var owned = newSeq[byte](value.len)
  for i, octet in value:
    owned[i] = octet # Capture caller bytes before publishing an immutable map.
  let writes = [StateWrite(key: accountKey, kind: StateWriteKind.Put,
      value: encoded.value), StateWrite(key: derived.value,
      kind: (if value.len == 0: StateWriteKind.Delete else: StateWriteKind.Put), value: owned)]
  var keys = previous.accountKeys
  if uint32(service) == uint32(self):
    let traced = prepareSelfAccountKeys(previous, writes)
    if traced.error != AccumulationEffectError.None:
      fail(traced.error) # Self trace capacity refusal precedes candidate map hashing.
    keys = traced.value # Foreign writes cannot impersonate self-key provenance.

  let modified = prepareModifiedAccounts(previous, [service])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, service, writes)
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply(writes)
  case changed.error
  of StateStoreError.None:
    discard # Publish only after both metadata and storage changes pass all inherited store ceilings.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Local map policy cannot masquerade as protocol FULL.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Merklization failure leaves the source owner untouched.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial successor on any store invariant failure.
  let candidate = if uint32(service) == uint32(self):
    selfAccountData(previous, changed.value, keys)
  else:
    successorData(previous, changed.value) # Foreign execution remains unsupported for parallel publication.
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  let successor = AccumulationEffects(data: PairData(source: data.source, regular: current,
    exceptional: data.exceptional))
  AccumulationEffectResult[AccumulationStorageChange](status: AccumulationEffectError.None,
    completed: AccumulationStorageChange(effects: successor, hadValue: hadValue,
      previousBytes: oldBytes))

proc recordAccumulationStorage*(effects: AccumulationEffects, key, value: openArray[byte],
    parameters: Parameters, limit: ByteLimit): AccumulationEffectResult[AccumulationStorageChange] =
  ## Preserve self-only callers through the same checked target operation and immutable trace publication.
  let data = effects.data
  if data == nil:
    return AccumulationEffectResult[AccumulationStorageChange](
        status: AccumulationEffectError.Uninitialized) # Defaults own no target.
  let current = data.regular.data
  assert current != nil # Private pairs retain both complete dimensions.
  recordAccumulationStorage(effects, key, value, parameters, limit,
      current.initial.contextInfo.value.service)

# Numeric order canonicalizes the host's set independently of little-endian wire ordering.
func comparePrivilege(left, right: AlwaysAccumulate): int =
  if uint32(left.service) < uint32(right.service): return -1 # Smaller service precedes larger service.
  if uint32(left.service) > uint32(right.service): return 1 # No subtraction or signed narrowing.
  if uint64(left.gas) < uint64(right.gas): return -1 # Group identical pairs for set deduplication.
  if uint64(left.gas) > uint64(right.gas): return 1 # Preserve distinct gas values for explicit ambiguity refusal.
  0

proc recordAccumulationBless*(effects: AccumulationEffects, source: PrivilegeState,
    config: PrivilegeConfig): AccumulationEffectResult[AccumulationEffects] =
  ## Replace regular privileges only for the current manager, preserving accounts, yield, provisions and checkpoint.
  ## Borrowed sequences stay stable during this call; accepted canonical bytes and snapshot own independent copies.
  ## Identical pairs are set duplicates; conflicting gas for a service refuses explicitly as AmbiguousPrivileges.
  # No partially encoded map or privilege owner escapes refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default pairs cannot authorize manager operations.
  let previous = data.regular.data
  assert previous != nil # Private effect constructors retain initialized current snapshots.
  let current = previous.privileges.privilegeInfo
  if current.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Invalid owners cannot fabricate authority.
  if uint32(previous.initial.contextInfo.value.service) != uint32(current.value.manager):
    fail(AccumulationEffectError.NotManager) # Authorization precedes proposed role/dictionary validation.
  if uint64(config.cores) != uint64(current.value.cores) or source.assigners.len !=
      current.value.cores:
    fail(AccumulationEffectError.InvalidState) # The current profile fixes the exact positional assigner count.
  if uint64(source.always.len) > uint64(config.maxAlways) or
      source.always.len > high(int) div sizeof(AlwaysAccumulate):
    fail(AccumulationEffectError.LimitExceeded) # Bound raw pair sorting/capture even when many entries would deduplicate.
  var ordered = newSeq[AlwaysAccumulate](source.always.len)
  for i, pair in source.always:
    ordered[i] = pair # Never sort or mutate the caller's borrowed sequence.
  ordered.sort(comparePrivilege)
  var unique: seq[AlwaysAccumulate] = @[]
  for pair in ordered:
    if unique.len != 0 and uint32(unique[unique.len-1].service) == uint32(pair.service):
      if uint64(unique[unique.len-1].gas) != uint64(pair.gas):
        fail(AccumulationEffectError.AmbiguousPrivileges) # No arbitrary first/last/max allowance interpretation.
      continue # Identical raw pairs are one member of the pinned set comprehension.
    unique.add(pair) # Prior item/native extent bounds also authorize this canonical subset.
  let canonical = PrivilegeState(manager: source.manager, delegator: source.delegator,
    registrar: source.registrar, assigners: source.assigners, always: unique)
  let encoded = privilegeStateEntry(canonical, config)
  if encoded.error in {PrivilegeError.LimitExceeded, PrivilegeError.LengthOverflow}:
    fail(AccumulationEffectError.LimitExceeded) # Codec byte/item ceilings are local, never HUH or WHO.
  if encoded.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # No invalid configuration or malformed canonical dictionary is accepted.
  let decoded = decodePrivilegeState(encoded.value.value, config)
  if decoded.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Encoding must supply exactly one independently owned canonical snapshot.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: encoded.value.key, kind: StateWriteKind.Put,
    value: encoded.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # C(12) and the typed privilege snapshot publish only after complete Merklization.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited complete-map limits remain independent of protocol gas.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Prior accounts and privileges survive failed hashing.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial map survives any other store invariant failure.
  let candidate = successorData(previous, changed.value, globalOnly = true)
  candidate.blessed = true # Only this proven C(12)-only mutation preserves scope; unsupported ancestry remains sticky.
  candidate.privileges = decoded.value.snapshot
  let currentContext = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: currentContext,
      exceptional: data.exceptional)))

proc recordAccumulationAssign*(effects: AccumulationEffects, core: AuthorizationCoreIndex,
    queue: openArray[AuthorizerHash], assigner: ServiceIndex, queues: AuthorizationConfig,
    privileges: PrivilegeConfig): AccumulationEffectResult[AccumulationEffects] =
  ## Replace one current queue and its assigner atomically, retaining the exceptional checkpoint.
  ## Borrowed hashes stay stable during this call; success owns independent canonical snapshots.
  ## Core/authority refusals precede candidate validation; local limits/backend failures expose no successor.
  # No candidate map or typed owner escapes a refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Defaults cannot authorize queue replacement.
  let previous = data.regular.data
  assert previous != nil # Every private pair retains complete children.
  let info = previous.privileges.privilegeInfo.value
  if uint64(core) >= uint64(info.cores):
    fail(AccumulationEffectError.InvalidCore) # Bound the nominal core before native narrowing.
  let selected = int(uint64(core))
  if uint32(previous.initial.contextInfo.value.service) != uint32(
      previous.privileges.privilegeAssignerAt(PrivilegeCoreIndex(uint64(core))).value):
    fail(AccumulationEffectError.NotAssigner) # Current authority, never initial roles, governs handoff.
  if queue.len != 80 or uint64(queues.cores) != uint64(info.cores) or
      uint64(privileges.cores) != uint64(info.cores) or
      previous.queues.authorizationCores.value != info.cores:
    fail(AccumulationEffectError.InvalidState) # Exact positional layouts must agree before capture.
  let cores = uint64(info.cores)
  if cores > uint64(queues.maxHashes) div 80 or cores > uint64(queues.maxBytes) div 2560 or
      cores > uint64(high(int) div 2560) or
      uint64(info.always) > uint64(privileges.maxAlways) or
      info.always > high(int) div sizeof(AlwaysAccumulate):
    fail(AccumulationEffectError.LimitExceeded) # Prove total hash/byte/native extents before allocations.
  var rows = newSeq[AuthorizerRow](info.cores)
  var roles = PrivilegeState(manager: info.manager, delegator: info.delegator,
    registrar: info.registrar, assigners: newSeq[ServiceIndex](info.cores),
    always: newSeq[AlwaysAccumulate](info.always))
  for c in 0..<info.cores:
    rows[c] = newSeq[AuthorizerHash](80) # Fixed per-core length and total extents are already bounded.
    roles.assigners[c] = previous.privileges.privilegeAssignerAt(PrivilegeCoreIndex(uint64(c))).value
    for i in 0..<80:
      rows[c][i] = (if c == selected: queue[i] else:
        previous.queues.authorizerAt(AuthorizationCoreIndex(uint64(c)), AuthorizationIndex(uint64(
            i))).value) # Preserve every other positional hash.
  roles.assigners[selected] = assigner
  for i in 0..<info.always:
    roles.always[i] = previous.privileges.alwaysAccumulateAt(PrivilegeEntryIndex(uint64(
        i))).value # Preserve canonical numeric dictionary order.
  let encodedQueues = authorizationEntry(AuthorizationKind.Queues, rows, queues)
  let encodedRoles = privilegeStateEntry(roles, privileges)
  if encodedQueues.error in {AuthorizationError.LimitExceeded, AuthorizationError.LengthOverflow} or
      encodedRoles.error in {PrivilegeError.LimitExceeded, PrivilegeError.LengthOverflow}:
    fail(AccumulationEffectError.LimitExceeded) # Component policies remain independent of guest success.
  if encodedQueues.error != AuthorizationError.None or encodedRoles.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Never publish an invalid candidate profile.
  let nextQueues = decodeAuthorization(AuthorizationKind.Queues, encodedQueues.value.value, queues)
  let nextRoles = decodePrivilegeState(encodedRoles.value.value, privileges)
  if nextQueues.error != AuthorizationError.None or nextRoles.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Require complete independent typed owners before publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([
    StateWrite(key: encodedQueues.value.key, kind: StateWriteKind.Put,
        value: encodedQueues.value.value),
    StateWrite(key: encodedRoles.value.key, kind: StateWriteKind.Put,
        value: encodedRoles.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # Both chapters have one fully Merklized successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited store ceilings never produce a guest code.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Original accounts and both typed owners survive hash failure.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value, globalOnly = true)
  candidate.assigned = true # Only this proven C(2)/C(12)-only operation may preserve account scope across a new map.
  candidate.queues = nextQueues.value.snapshot
  candidate.privileges = nextRoles.value.snapshot
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc recordAccumulationDesignate*(effects: AccumulationEffects, validators: openArray[
    StateValidator], config: ValidatorStateConfig): AccumulationEffectResult[AccumulationEffects] =
  ## Replace the complete regular staging roster only for the current delegator, preserving the checkpoint.
  ## Borrowed records stay stable during this call; accepted canonical bytes and typed snapshot own their copies.
  ## InvalidValidatorCount/NotDelegator are protocol refusals; component/store/backend failures expose no successor.
  # Refuse before publishing a partial map or roster owner.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default pairs cannot authorize delegation.
  let previous = data.regular.data
  assert previous != nil # All private pair constructors retain complete current versions.
  let roles = previous.privileges.privilegeInfo.value
  if uint64(config.cores) != uint64(roles.cores):
    fail(AccumulationEffectError.InvalidState) # The complete state fixes the profile, not the proposed roster.
  if validators.len < 6 or validators.len mod 3 != 0 or validators.len div 3 > roles.cores:
    fail(AccumulationEffectError.InvalidValidatorCount) # Counts vary within valcount, independently of the initial roster length.
  if uint32(previous.initial.contextInfo.value.service) != uint32(roles.delegator):
    fail(AccumulationEffectError.NotDelegator) # Always use current roles after any bless handoff.
  let encoded = validatorEntry(ValidatorChapter.Staging, validators, config)
  if encoded.error in {StateComponentError.LimitExceeded, StateComponentError.LengthOverflow}:
    fail(AccumulationEffectError.LimitExceeded) # The codec preflights count, typed/native extents and canonical bytes.
  if encoded.error != StateComponentError.None:
    fail(AccumulationEffectError.InvalidState) # No invalid candidate or profile can fabricate a roster.
  let decoded = decodeStateValidators(encoded.value.value, config)
  if decoded.error != StateComponentError.None:
    fail(AccumulationEffectError.InvalidState) # Require one independent canonical typed snapshot before publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: encoded.value.key, kind: StateWriteKind.Put,
    value: encoded.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # Both representations share one fully Merklized successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited complete-map policy is independent of guest gas.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Prior serialized state and typed roster remain valid.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value, globalOnly = true)
  candidate.designated = true # This proven C(7)-only mutation preserves account scope without erasing unsupported ancestry.
  candidate.staging = decoded.value.value
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc recordAccumulationNew*(effects: AccumulationEffects, source: AccumulationNewService,
    parameters: Parameters, probes: ServiceProbeLimit, funder: ServiceIndex,
        mode: AccumulationFundingMode): AccumulationEffectResult[AccumulationServiceChange] =
  ## Create one service with its empty code request, selected funding debit and current allocation cursor atomically.
  ## Uses current roles/accounts for authorization/funding, and pinned invocation-start membership for check(i).
  ## Protocol HUH/CASH/FULL refusals are distinct from local malformed state, probe/store limits and backend failure.
  # No partial account, request, cursor or effects owner escapes a refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationServiceChange](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Defaults have no creator or allocation provenance.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Funding never uses a fabricated deposit schedule.
  if uint32(source.length) >= high(uint32)-1:
    fail(AccumulationEffectError.InvalidLength) # Validate public proposals before funding, probing or namespace hashing.
  let previous = data.regular.data
  assert previous != nil # Private pairs retain complete current contexts.
  let self = previous.initial.contextInfo.value.service
  let roles = previous.privileges.privilegeInfo.value
  let selectedFunder = currentAccountMetadata(previous.accounts, funder)
  if selectedFunder.error != AccumulationEffectError.None:
    if selectedFunder.error == AccumulationEffectError.UnknownService and uint32(funder) == uint32(self):
      fail(AccumulationEffectError.MalformedState) # Never reconstruct a missing invoker.
    fail(selectedFunder.error) # WHO precedes mode/authority/manager checks.
  let selection = uint64(mode)
  if selection > 3:
    fail(AccumulationEffectError.NotRequested) # Preserve the entire register domain without masked aliases.
  var payer = selectedFunder.value
  if selection in [1'u64, 3'u64] or uint32(funder) != uint32(self):
    let authority = effectiveSupervisor(previous.accounts, funder, payer)
    if authority.error != AccumulationEffectError.None:
      fail(authority.error) # Malformed provenance grants neither liquid nor protected authority.
    if uint32(authority.value) != uint32(self):
      fail(AccumulationEffectError.NotRequested) # Protected source funds belong only to the effective supervisor.
  if uint64(source.gratis) != 0 and uint32(self) != uint32(roles.manager):
    fail(AccumulationEffectError.NotManager) # Gratis remains the invoker's current manager privilege.
  let creator = if uint32(funder) == uint32(self): selectedFunder else: currentAccountMetadata(
      previous.accounts, self)
  if creator.error != AccumulationEffectError.None:
    fail(AccumulationEffectError.MalformedState) # Child incarnation must come from the real current invoker.
  let balance = if selection in [1'u64, 3'u64]: uint64(payer.supervisorBalance) else: uint64(payer.balance)
  let gratis = uint64(source.gratis)
  let slot = previous.initial.contextInvocation.value.bootstrapInfo.value.slot
  var child = ServiceMetadata(codeHash: source.codeHash, depositOffset: source.gratis,
    minimumAccumulationGas: source.accumulationGas, minimumTransferGas: source.transferGas,
    storageItems: AccountStorageItems(2), storageBytes: AccountStorageBytes(81'u64+uint64(uint32(
        source.length))),
    created: AccountSlot(uint32(slot)), lastAccumulation: AccountSlot(0),
    supervisor: self, supervisorCreated: creator.value.created, supervisorBalance: AccountBalance(
        0), parent: self) # E4 length+81 fits uint64.
  var low = 0'u64
  var upper = 0'u64
  if gratis > high(uint64)-balance:
    upper = 1 # Preserve the carry of creator balance plus proposed gratis.
    low = gratis-(high(uint64)-balance)-1
  else:
    low = balance+gratis # This branch proves the two-term addition fits.
  if not consumeAccountDeposit(child, parameters, low, upper):
    fail(AccumulationEffectError.InsufficientCash) # Child's mathematical threshold exceeds all available creator balance.
  let minimum = (if upper != 0 or low >= balance: 0'u64 else: balance-low)
  if selection in [0'u64, 1'u64]:
    child.balance = AccountBalance(minimum) # Destination liquid pool receives exactly the mathematical threshold.
  else:
    child.supervisorBalance = AccountBalance(minimum) # Protected destination starts with zero liquid funds.
  if selection in [1'u64, 3'u64]:
    payer.supervisorBalance = AccountBalance(balance-minimum) # Selected-pool consumption proves no underflow.
  else:
    payer.balance = AccountBalance(balance-minimum) # Never borrow liquidity from the other pool.
  if not funded(payer, parameters):
    fail(AccumulationEffectError.InsufficientCash) # The debit must also preserve the creator's own threshold.
  var selected = previous.nextService
  var next = previous.nextService
  let desired = uint64(source.desired)
  if uint32(self) == uint32(roles.registrar) and desired < FirstPublicService:
    selected = ServiceIndex(uint32(desired)) # Proven reserved-domain narrowing; no self/low-bit alias is invented.
    let occupied = previous.accounts.lookup(chapterServiceKey(StateChapter(255), selected))
    if occupied.error == StateStoreError.None:
      fail(AccumulationEffectError.ServiceExists) # FULL is only for a registrar's current reserved-ID collision.
    if occupied.error != StateStoreError.MissingKey:
      fail(AccumulationEffectError.InvalidState) # Invalid complete maps cannot fabricate absence.
  else:
    let occupied = previous.accounts.lookup(chapterServiceKey(StateChapter(255), selected))
    if occupied.error != StateStoreError.MissingKey:
      fail(AccumulationEffectError.InvalidState) # An automatic collision cannot overwrite an existing service.
    let advanced = nextAccumulationService(previous.initial.contextAccounts.value, selected, probes)
    if advanced.error == AccumulationInvocationError.LimitExceeded:
      fail(AccumulationEffectError.LimitExceeded) # Probe exhaustion publishes neither child nor cursor advancement.
    if advanced.error != AccumulationInvocationError.None:
      fail(AccumulationEffectError.InvalidState) # Preserve the pinned public-domain/membership invariant.
    next = advanced.value
  let request = serviceRequestEntry(selected, ServicePreimageHash(array[32, byte](source.codeHash)),
    source.length, requestedHistory(), RequestEntryConfig(keyBytes: ByteLimit(32),
      history: RequestHistoryConfig(items: ElementLimit(0), maxBytes: ByteLimit(1))))
  if request.error != RequestError.None:
    fail(AccumulationEffectError.BackendFailure) # Fixed canonical request policy is sufficient; failed derivation never changes namespace.
  let parentEntry = serviceMetadataEntry(funder, payer, ByteLimit(ServiceMetadataBytes)).value
  let childEntry = serviceMetadataEntry(selected, child, ByteLimit(ServiceMetadataBytes)).value
  let captured = prepareCreatedAccount(previous, selected, request.value.key)
  if captured.error != AccumulationEffectError.None:
    fail(captured.error) # Creation capacity precedes account-map hashing and cursor publication.
  let modified = prepareModifiedAccounts(previous, [funder])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, [
    AccumulationAccountWriteFact(service: funder, key: parentEntry.key),
    AccumulationAccountWriteFact(service: selected, key: childEntry.key),
    AccumulationAccountWriteFact(service: selected, key: request.value.key)])
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([
    StateWrite(key: parentEntry.key, kind: StateWriteKind.Put, value: parentEntry.value),
    StateWrite(key: childEntry.key, kind: StateWriteKind.Put, value: childEntry.value),
    StateWrite(key: request.value.key, kind: StateWriteKind.Put, value: request.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # All three entries are one fully Merklized successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited item/write/byte policies are independent of protocol CASH/FULL.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Source accounts and cursor survive even delayed hash failure.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value)
  if uint32(funder) == uint32(self) and previous.accountScope !=
      AccumulationAccountScope.Unsupported and uint64(previous.createdLimit) != 0:
    candidate.accountScope = if previous.accountScope == AccumulationAccountScope.DeletedAccounts:
      AccumulationAccountScope.DeletedAccounts else: AccumulationAccountScope.CreatedAccounts # New preserves earlier ejection facts.
  candidate.created = captured.value # Enabled creation membership survives independently of legacy account-scope publication.
  candidate.nextService = next
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationServiceChange](status: AccumulationEffectError.None,
    completed: AccumulationServiceChange(service: selected, effects: AccumulationEffects(data:
    PairData(source: data.source, regular: current, exceptional: data.exceptional))))

proc recordAccumulationNew*(effects: AccumulationEffects, source: AccumulationNewService,
    parameters: Parameters, probes: ServiceProbeLimit): AccumulationEffectResult[
        AccumulationServiceChange] =
  ## Preserve self/liquid creation callers through the complete checked funding operation.
  let data = effects.data
  if data == nil:
    return AccumulationEffectResult[AccumulationServiceChange](
        status: AccumulationEffectError.Uninitialized) # Defaults own no funding source.
  let current = data.regular.data
  assert current != nil # Private pairs retain both initialized dimensions.
  recordAccumulationNew(effects, source, parameters, probes,
      current.initial.contextInfo.value.service, AccumulationFundingMode(0))

proc recordAccumulationUpgrade*(effects: AccumulationEffects, codeHash: CodeHash,
    accumulationGas, transferGas: Gas, target: ServiceIndex): AccumulationEffectResult[
        AccumulationEffects] =
  ## Replace a current self/supervised account's code hash and minimum gas fields, preserving other implications and checkpoints.
  ## Inputs are copied nominal values; no offered preimage, privilege or funding condition is required.
  ## Canonical metadata and inherited store policy are checked before one complete successor can escape.
  # Refusals expose neither a partial account map nor an alternative effect version.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default effects cannot select a target account.
  let previous = data.regular.data
  assert previous != nil # Private pairs retain complete current versions.
  let self = previous.initial.contextInfo.value.service
  let key = chapterServiceKey(StateChapter(255), target)
  let found = previous.accounts.lookup(key)
  if found.error == StateStoreError.MissingKey and uint32(target) != uint32(self):
    fail(AccumulationEffectError.UnknownService) # A genuinely absent foreign target selects protocol WHO.
  if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Never fabricate or repair the selected account's metadata.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Only canonical complete metadata may be changed.
  var metadata = decoded.value.metadata
  if uint32(target) != uint32(self):
    # Effective supervision binds the current invoker's incarnation, not merely its reusable service ID.
    let invoker = previous.accounts.lookup(chapterServiceKey(StateChapter(255), self))
    if invoker.error != StateStoreError.None or invoker.value.byteLength != ServiceMetadataBytes:
      fail(AccumulationEffectError.MalformedState) # No malformed current identity may authorize a mutation.
    let identity = decodeServiceMetadata(invoker.value.bytes, ByteLimit(ServiceMetadataBytes))
    if identity.error != ServiceMetadataError.None:
      fail(AccumulationEffectError.MalformedState) # Preserve canonical metadata requirements for both participants.
    if uint32(metadata.supervisor) != uint32(self) or
        uint32(metadata.supervisorCreated) != uint32(identity.value.metadata.created):
      fail(AccumulationEffectError.NotRequested) # A missing/recreated supervisor falls back to the foreign target, so this invoker gets HUH.
  metadata.codeHash = codeHash
  metadata.minimumAccumulationGas = accumulationGas
  metadata.minimumTransferGas = transferGas
  let encoded = serviceMetadataEntry(target, metadata, ByteLimit(ServiceMetadataBytes)).value
  let modified = prepareModifiedAccounts(previous, [target])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, [AccumulationAccountWriteFact(service: target,
      key: encoded.key)])
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: key, kind: StateWriteKind.Put,
      value: encoded.value)])
  case changed.error
  of StateStoreError.None:
    discard # All three fields share one fully Merklized metadata replacement.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Local policy cannot fabricate a guest resource code.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Existing accounts and every retained owner survive hashing refusal.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value, selfMetadata = uint32(target) == uint32(self))
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc recordAccumulationUpgrade*(effects: AccumulationEffects, codeHash: CodeHash,
    accumulationGas, transferGas: Gas): AccumulationEffectResult[AccumulationEffects] =
  ## Preserve the self-only API while sharing the target operation's canonical metadata and atomicity checks.
  let data = effects.data
  if data == nil:
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized) # Defaults own no invoker identity.
  let current = data.regular.data
  assert current != nil # Private effect pairs retain both initialized dimensions.
  recordAccumulationUpgrade(effects, codeHash, accumulationGas, transferGas,
      current.initial.contextInfo.value.service)

proc recordAccumulationSupervisor*(effects: AccumulationEffects, target, supervisor: ServiceIndex):
    AccumulationEffectResult[AccumulationEffects] =
  ## Reassign only an effectively supervised target, after checking both current nominal account identities.
  ## UnknownService maps to WHO, NotRequested to HUH; every local failure retains the original account/checkpoint owners.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # A default pair owns no invocation authority.
  let previous = data.regular.data
  assert previous != nil # Private pairs retain complete initialized dimensions.
  let self = previous.initial.contextInfo.value.service
  let selected = currentAccountMetadata(previous.accounts, target)
  if selected.error != AccumulationEffectError.None:
    fail(selected.error) # Target existence/canonicality is established before any authority check.
  let nominee = currentAccountMetadata(previous.accounts, supervisor)
  if nominee.error != AccumulationEffectError.None:
    fail(nominee.error) # Even an unauthorized caller receives WHO for a missing nominee.
  let authority = effectiveSupervisor(previous.accounts, target, selected.value)
  if authority.error != AccumulationEffectError.None:
    fail(authority.error) # Keep malformed supervisor provenance as a local refusal.
  if uint32(authority.value) != uint32(self):
    fail(AccumulationEffectError.NotRequested) # Only effective supervision authorizes this host, including a self target.
  var metadata = selected.value
  metadata.supervisor = supervisor
  metadata.supervisorCreated = nominee.value.created
  let encoded = serviceMetadataEntry(target, metadata, ByteLimit(ServiceMetadataBytes)).value
  let modified = prepareModifiedAccounts(previous, [target])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, [AccumulationAccountWriteFact(service: target,
      key: encoded.key)])
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: encoded.key, kind: StateWriteKind.Put,
      value: encoded.value)])
  case changed.error
  of StateStoreError.None:
    discard # Both supervisor fields are one fully Merklized metadata successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Local policy cannot become a fabricated guest code.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # No partial target or effect version escapes hash refusal.
  else:
    fail(AccumulationEffectError.InvalidState) # Preserve every retained owner on other store invariants.
  let candidate = successorData(previous, changed.value, selfMetadata = uint32(target) == uint32(self))
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source,
      regular: AccumulationEffectContext(data: candidate), exceptional: data.exceptional)))

proc effectTransferAt*(context: AccumulationEffectContext, index: AccumulationTransferIndex):
    AccumulationEffectResult[DeferredTransfer] =
  ## Copy one complete outgoing transfer by its ordinal; no mutable memo or backing sequence escapes.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[DeferredTransfer](
        status: AccumulationEffectError.Uninitialized) # Defaults own no transfers.
  if uint64(index) >= uint64(data.transfers.values.len):
    return AccumulationEffectResult[DeferredTransfer](
        status: AccumulationEffectError.InvalidIndex) # Bound before native narrowing.
  AccumulationEffectResult[DeferredTransfer](status: AccumulationEffectError.None,
    completed: data.transfers.values[int(uint64(index))])

proc prepareAccumulationTransfer*(effects: AccumulationEffects,
    destination: AccumulationTransferDestination, amount: TransferBalance, gas: Gas,
    memo: TransferMemo, parameters: Parameters, funder: ServiceIndex,
    mode: AccumulationFundingMode): AccumulationEffectResult[PreparedAccumulationTransfer] =
  ## Validate both accounts, authority, LOW and CASH without hashing; retain this exact source version.
  ## The selected source pool funds one deferred record, whose destination flag selects the future credit pool.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[PreparedAccumulationTransfer](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # No default owner can authorize a debit.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Funding requires an actual deposit schedule.
  let previous = data.regular.data
  assert previous != nil # Private constructors retain complete current snapshots.
  let original = currentAccountMetadata(previous.accounts, funder)
  if original.error != AccumulationEffectError.None:
    if original.error == AccumulationEffectError.UnknownService and uint32(funder) == uint32(
        previous.initial.contextInfo.value.service):
      fail(AccumulationEffectError.MalformedState) # Never fabricate a missing invoker.
    fail(original.error) # Source WHO precedes authority and minimum-gas checks.
  if uint64(destination) > uint64(high(uint32)):
    fail(AccumulationEffectError.UnknownService) # No low-bit alias for a full-width destination.
  let target = ServiceIndex(uint32(uint64(destination)))
  let recipient = currentAccountMetadata(previous.accounts, target)
  if recipient.error != AccumulationEffectError.None:
    fail(recipient.error) # Both accounts must exist before authority HUH.
  let selection = uint64(mode)
  if selection > 3:
    fail(AccumulationEffectError.NotRequested) # Undefined modes never mask into a valid balance choice.
  let self = previous.initial.contextInfo.value.service
  var metadata = original.value
  if selection in [1'u64, 3'u64] or uint32(funder) != uint32(self):
    let authority = effectiveSupervisor(previous.accounts, funder, metadata)
    if authority.error != AccumulationEffectError.None:
      fail(authority.error) # Malformed supervision grants no funding authority.
    if uint32(authority.value) != uint32(self):
      fail(AccumulationEffectError.NotRequested) # Protected source funds always require effective supervision.
  if uint64(gas) < uint64(recipient.value.minimumTransferGas):
    fail(AccumulationEffectError.TransferGasLow) # LOW follows authority and precedes funding CASH.
  let balance = if selection in [1'u64, 3'u64]: uint64(metadata.supervisorBalance) else: uint64(
      metadata.balance)
  if uint64(amount) > balance:
    fail(AccumulationEffectError.InsufficientCash) # Only the selected source pool can fund the debit.
  if selection in [1'u64, 3'u64]:
    metadata.supervisorBalance = AccountBalance(balance-uint64(amount)) # Proven unsigned subtraction.
  else:
    metadata.balance = AccountBalance(balance-uint64(amount)) # Preserve the unselected protected pool.
  if not funded(metadata, parameters):
    fail(AccumulationEffectError.InsufficientCash) # Both remaining pools contribute to the source threshold.
  let transfer = DeferredTransfer(source: funder, destination: target,
      destinationSupervisor: selection >= 2, amount: amount, gas: gas, memo: memo)
  let plan = PreparedAccumulationTransfer(data: TransferPlanData(source: effects,
      metadata: metadata, transfer: transfer))
  AccumulationEffectResult[PreparedAccumulationTransfer](status: AccumulationEffectError.None,
      completed: plan)

proc prepareAccumulationTransfer*(effects: AccumulationEffects,
    destination: AccumulationTransferDestination, amount: TransferBalance, gas: Gas,
    memo: TransferMemo, parameters: Parameters): AccumulationEffectResult[
        PreparedAccumulationTransfer] =
  ## Preserve self/liquid callers through the complete deferred funding operation.
  let data = effects.data
  if data == nil:
    return AccumulationEffectResult[PreparedAccumulationTransfer](
        status: AccumulationEffectError.Uninitialized) # Defaults retain no source account.
  let previous = data.regular.data
  assert previous != nil # Successful preparation retains a current context.
  prepareAccumulationTransfer(effects, destination, amount, gas, memo, parameters,
      previous.initial.contextInfo.value.service, AccumulationFundingMode(0))

proc commitAccumulationTransfer*(prepared: PreparedAccumulationTransfer, limit: ElementLimit):
    AccumulationEffectResult[AccumulationEffects] =
  ## Publish the bound creator debit and one ordered append atomically; callers must first charge conditional host gas.
  ## Reusing a plan produces successors of the same retained version, never appends to an ambient replacement state.
  # No partially debited account or detached transfer sequence escapes any refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let plan = prepared.data
  if plan == nil:
    fail(AccumulationEffectError.Uninitialized) # A default handle grants no prepared transfer.
  let data = plan.source.data
  assert data != nil # Only successful preparation creates a source-bound plan.
  let previous = data.regular.data
  assert previous != nil # Prepared immutable pairs always retain their current child.
  let count = previous.transfers.values.len
  if uint64(count) >= uint64(limit) or count >= high(int) div sizeof(DeferredTransfer):
    fail(AccumulationEffectError.LimitExceeded) # Prove count+1 and typed allocation extent before appending.
  var transfers = newSeq[DeferredTransfer](count+1)
  for i in 0..<count:
    transfers[i] = previous.transfers.values[i] # Copy fixed values in exact existing order, including duplicates.
  transfers[count] = plan.transfer
  let encoded = serviceMetadataEntry(plan.transfer.source, plan.metadata, ByteLimit(
      ServiceMetadataBytes)).value
  let modified = prepareModifiedAccounts(previous, [plan.transfer.source])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, [AccumulationAccountWriteFact(
      service: plan.transfer.source, key: encoded.key)])
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: encoded.key, kind: StateWriteKind.Put,
      value: encoded.value)])
  case changed.error
  of StateStoreError.None:
    discard # Only a fully Merklized creator debit can accompany the appended transfer.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited store policy remains an explicit local refusal.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Old accounts and outgoing owners survive hashing failure.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  # Preserve bounded self proofs only when the actual debit belongs to the invoker.
  let self = previous.initial.contextInfo.value.service
  let candidate = successorData(previous, changed.value, selfMetadata = uint32(
      plan.transfer.source) == uint32(self))
  candidate.transfers = TransferSetData(values: transfers)
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc recordAccumulationDirectTransfer*(effects: AccumulationEffects, funder: ServiceIndex,
    destination: AccumulationTransferDestination, amount: TransferBalance,
    mode: AccumulationFundingMode, parameters: Parameters): AccumulationEffectResult[
        AccumulationEffects] =
  ## Apply current direct Omega_T with both-endpoint authority, no memo and no deferred output.
  ## Publish both pool changes atomically; same-account modes1/2 operate on one combined metadata record.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Defaults cannot authorize either endpoint.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Funding requires the actual deposit schedule.
  let previous = data.regular.data
  assert previous != nil # Private pairs retain initialized current dimensions.
  let self = previous.initial.contextInfo.value.service
  let source = currentAccountMetadata(previous.accounts, funder)
  if source.error != AccumulationEffectError.None:
    if source.error == AccumulationEffectError.UnknownService and uint32(funder) == uint32(self):
      fail(AccumulationEffectError.MalformedState) # A missing invoker is invalid local provenance.
    fail(source.error) # WHO precedes every authority and cash refusal.
  if uint64(destination) > uint64(high(uint32)):
    fail(AccumulationEffectError.UnknownService) # Preserve the whole destination register domain.
  let target = ServiceIndex(uint32(uint64(destination)))
  let recipient = currentAccountMetadata(previous.accounts, target)
  if recipient.error != AccumulationEffectError.None:
    fail(recipient.error) # Both accounts exist before HUH can be selected.
  let selection = uint64(mode)
  let same = uint32(funder) == uint32(target)
  if selection > 3 or (same and selection in [0'u64, 3'u64]):
    fail(AccumulationEffectError.NotRequested) # Direct same-pool self transfers are explicitly forbidden.
  if selection in [1'u64, 3'u64] or uint32(funder) != uint32(self):
    let authority = effectiveSupervisor(previous.accounts, funder, source.value)
    if authority.error != AccumulationEffectError.None:
      fail(authority.error) # Never reconstruct malformed supervision.
    if uint32(authority.value) != uint32(self):
      fail(AccumulationEffectError.NotRequested) # Source protected funds require effective supervisor authority.
  if uint32(target) != uint32(self):
    let authority = effectiveSupervisor(previous.accounts, target, recipient.value)
    if authority.error != AccumulationEffectError.None:
      fail(authority.error) # Direct credits require actual destination authority too.
    if uint32(authority.value) != uint32(self):
      fail(AccumulationEffectError.NotRequested) # No arbitrary direct credit bypasses destination execution.
  var paid = source.value
  let debit = uint64(amount)
  let balance = if selection in [1'u64, 3'u64]: uint64(paid.supervisorBalance) else: uint64(paid.balance)
  if debit > balance:
    fail(AccumulationEffectError.InsufficientCash) # Prove selected-pool subtraction before computing either successor.
  if selection in [1'u64, 3'u64]:
    paid.supervisorBalance = AccountBalance(balance-debit) # Preserve liquid source funds.
  else:
    paid.balance = AccountBalance(balance-debit) # Preserve protected source funds.
  if not same and not funded(paid, parameters):
    fail(AccumulationEffectError.InsufficientCash) # A distinct destination cannot fund the source threshold.
  var credited = if same: paid else: recipient.value
  let credit = if selection >= 2: uint64(credited.supervisorBalance) else: uint64(credited.balance)
  if debit > high(uint64)-credit:
    fail(AccumulationEffectError.InvalidState) # Unrepresentable canonical balance grants no partial credit or guest code.
  if selection >= 2:
    credited.supervisorBalance = AccountBalance(credit+debit) # The preceding bound proves addition fits.
  else:
    credited.balance = AccountBalance(credit+debit) # Same-account cross-pool credit follows the selected debit.
  if same:
    paid = credited # One account contains both prospective fields before its aggregate funding check.
    if not funded(paid, parameters):
      fail(AccumulationEffectError.InsufficientCash) # Cross-pool moves preserve, rather than temporarily lower, total funding.
  let debitEntry = serviceMetadataEntry(funder, paid, ByteLimit(ServiceMetadataBytes)).value
  var writes = @[StateWrite(key: debitEntry.key, kind: StateWriteKind.Put, value: debitEntry.value)]
  if not same:
    let creditEntry = serviceMetadataEntry(target, credited, ByteLimit(ServiceMetadataBytes)).value
    writes.add(StateWrite(key: creditEntry.key, kind: StateWriteKind.Put,
        value: creditEntry.value)) # Distinct endpoints require one atomic two-write batch.
  let modified = prepareModifiedAccounts(previous, [funder, target])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = (if same:
    prepareAccountWriteFacts(previous, [AccumulationAccountWriteFact(service: funder,
        key: debitEntry.key)])
  else:
    prepareAccountWriteFacts(previous, [AccumulationAccountWriteFact(service: funder,
        key: debitEntry.key), AccumulationAccountWriteFact(service: target, key: chapterServiceKey(
            StateChapter(255), target))]))
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply(writes)
  case changed.error
  of StateStoreError.None:
    discard # Neither field or endpoint is visible before complete Merklization succeeds.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Local store ceilings never become guest CASH.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # No debit survives a failed destination credit.
  else:
    fail(AccumulationEffectError.InvalidState) # Preserve both prior owners on invariant failure.
  let candidate = successorData(previous, changed.value, selfMetadata = same and uint32(funder) ==
      uint32(self))
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
      completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
          exceptional: data.exceptional)))

proc recordAccumulationEject*(effects: AccumulationEffects, target: AccumulationEjectTarget,
    parameters: Parameters): AccumulationEffectResult[AccumulationEffects] =
  ## Remove an empty junior created before this invocation and reclaim both balances into self liquid funds.
  ## Current Omega_J authenticates the effective supervisor by identifier and creation slot, with no hash input.
  ## UnknownService is WHO; self, unauthorized, newly created or nonempty accounts return NotRequested/HUH.
  ## Complete metadata deletion and caller credit require two bounded atomic writes; overflow refuses locally.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default pairs cannot authorize account reclamation.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Preserve the validated invocation-profile contract.
  let previous = data.regular.data
  assert previous != nil # Initialized pairs retain a complete regular account owner.
  let self = previous.initial.contextInfo.value.service
  if uint64(target) > uint64(high(uint32)):
    fail(AccumulationEffectError.UnknownService) # Full-width IDs never alias a valid service after narrowing.
  let service = ServiceIndex(uint32(uint64(target)))
  let accountKey = chapterServiceKey(StateChapter(255), service)
  let found = previous.accounts.lookup(accountKey)
  if found.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Membership precedes every eligibility condition.
  if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Corrupt metadata is a local state refusal, not WHO.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Require one exact current canonical metadata encoding.
  if uint32(service) == uint32(self):
    fail(AccumulationEffectError.NotRequested) # A present invoker cannot eject itself, even as its own supervisor.
  let creator = previous.accounts.lookup(chapterServiceKey(StateChapter(255), self))
  if creator.error != StateStoreError.None or creator.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Reclamation requires genuine current invoker metadata.
  let original = decodeServiceMetadata(creator.value.bytes, ByteLimit(ServiceMetadataBytes))
  if original.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Never repair the invoker or fabricate its creation slot.
  let account = decoded.value.metadata
  var metadata = original.value.metadata
  let time = previous.initial.contextInvocation.value.bootstrapInfo.value.slot
  if uint32(account.supervisor) != uint32(self) or
      uint32(account.supervisorCreated) != uint32(metadata.created) or
      uint32(account.created) == uint32(time) or uint32(account.storageItems) != 0:
    fail(AccumulationEffectError.NotRequested) # A missing/recreated supervisor falls back to the target itself and cannot authorize this other invoker.
  for amount in [uint64(account.balance), uint64(account.supervisorBalance)]:
    if amount > high(uint64)-uint64(metadata.balance):
      fail(AccumulationEffectError.InvalidState) # Neither component may overflow the reclaimed liquid balance.
    metadata.balance = AccountBalance(uint64(metadata.balance)+amount) # The preceding comparison proves this sum fits.
  let captured = prepareDeletedAccount(previous, service)
  if captured.error != AccumulationEffectError.None:
    fail(captured.error) # Bound immutable membership proof capacity before Merklization or publication.
  let credited = serviceMetadataEntry(self, metadata, ByteLimit(ServiceMetadataBytes)).value
  let modified = prepareModifiedAccounts(previous, [self, service])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, [
    AccumulationAccountWriteFact(service: service, key: accountKey),
    AccumulationAccountWriteFact(service: self, key: credited.key)])
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([
    StateWrite(key: accountKey, kind: StateWriteKind.Delete),
    StateWrite(key: credited.key, kind: StateWriteKind.Put, value: credited.value)])
  case changed.error
  of StateStoreError.None:
    discard # One complete-map commit publishes deletion and both reclaimed balance components.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited two-write/byte/node policy is independent of protocol eligibility.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # A failed trie hash leaves both original accounts untouched.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial successor escapes other map invariant failures.
  let candidate = successorData(previous, changed.value)
  if previous.accountScope != AccumulationAccountScope.Unsupported and uint64(
      previous.deletedLimit) != 0:
    candidate.accountScope = AccumulationAccountScope.DeletedAccounts # Successful bounded ejections alone certify foreign removals.
    candidate.deleted = captured.value
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc effectServiceRequestHistory*(context: AccumulationEffectContext, service: ServiceIndex,
    hash: ServicePreimageHash,
    length: RequestLength): AccumulationEffectResult[RequestHistory] =
  ## Copy the selected current service's exact request history; NotRequested distinguishes absence from a present empty history.
  ## Captures at most thirteen canonical bytes; malformed/trailing state and namespace backend failures expose no history.
  # Default and failed reads carry only their reason, never a fabricated requested state.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[RequestHistory](status: reason)
  let data = context.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # No default context can supply a service identity or account backing.
  if uint32(length) >= high(uint32)-1:
    fail(AccumulationEffectError.InvalidLength) # Invalid E4 domains never become namespace backend failures.
  let account = data.accounts.lookup(chapterServiceKey(StateChapter(255), service))
  if account.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Missing service is distinct from an absent request.
  if account.error != StateStoreError.None or account.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # No malformed account may supply a request namespace.
  if decodeServiceMetadata(account.value.bytes, ByteLimit(ServiceMetadataBytes)).error !=
      ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Keep canonical metadata checks independent of history decoding.
  let key = serviceRequestKey(service, hash, length, ByteLimit(32))
  if key.error != RequestError.None:
    fail(AccumulationEffectError.BackendFailure) # Namespace hashing refusal cannot turn into NONE.
  let found = data.accounts.lookup(key.value)
  if found.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.NotRequested) # A missing pair has no requested/available history payload.
  if found.error != StateStoreError.None or found.value.byteLength > 13:
    fail(AccumulationEffectError.MalformedState) # Bound the copied record before decoding.
  let decoded = decodeRequestHistory(found.value.bytes,
    RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))
  if decoded.error != RequestError.None or decoded.value.consumed != found.value.byteLength:
    fail(AccumulationEffectError.MalformedState) # Prefix acceptance cannot hide trailing or malformed canonical state.
  AccumulationEffectResult[RequestHistory](status: AccumulationEffectError.None,
    completed: decoded.value.history)

proc effectRequestHistory*(context: AccumulationEffectContext, hash: ServicePreimageHash,
    length: RequestLength): AccumulationEffectResult[RequestHistory] =
  ## Select the invocation's actual self service while retaining the same current immutable account backing.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[RequestHistory](status: AccumulationEffectError.Uninitialized)
  effectServiceRequestHistory(context, data.initial.contextInfo.value.service, hash, length)

proc recordAccumulationSolicit*(effects: AccumulationEffects, hash: ServicePreimageHash,
    length: RequestLength, parameters: Parameters, target: ServiceIndex): AccumulationEffectResult[
        AccumulationEffects] =
  ## Create an empty self/supervised request or restore an unavailable history using the invocation's own slot.
  ## NotRequested is HUH for other shapes; StorageFull is FULL after exact prospective funding. Balance and existing preimages never change.
  ## Publish metadata/history atomically under inherited write limits; InvalidState rejects unrepresentable footprint counters.
  # All refused/default operations carry only a reason, never a partially requested successor.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # A default pair supplies no request or invocation provenance.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Funding cannot use a fabricated schedule.
  let previous = data.regular.data
  assert previous != nil # Private pair construction retains initialized current contexts.
  if uint32(length) >= high(uint32)-1:
    fail(AccumulationEffectError.InvalidLength) # Current length HUH precedes all target/history work.
  let self = previous.initial.contextInfo.value.service
  let selected = authorizedAccountMetadata(previous, target)
  if selected.error != AccumulationEffectError.None:
    fail(selected.error) # WHO and authority HUH precede request namespace hashing.
  let prior = data.regular.effectServiceRequestHistory(target, hash, length)
  var history = requestedHistory()
  var fresh = false
  case prior.error
  of AccumulationEffectError.NotRequested:
    fresh = true # An absent pair adds one request and its two-item storage footprint.
  of AccumulationEffectError.None:
    if prior.value.state != RequestState.Unavailable:
      fail(AccumulationEffectError.NotRequested) # Requested, available and restored shapes are HUH before funding.
    let slot = previous.initial.contextInvocation.value.bootstrapInfo.value.slot
    history = reavailableHistory(prior.value.availableFrom, prior.value.unavailableFrom,
      RequestSlot(uint32(slot))) # Append the actual invocation time without age checks or timestamp repair.
  else:
    fail(prior.error) # Preserve malformed state and backend errors from the bounded current-history reader.
  let accountKey = chapterServiceKey(StateChapter(255), target)
  var metadata = selected.value
  if fresh:
    let added = 81'u64+uint64(uint32(length)) # E4 length plus fixed overhead is below 2^33.
    if uint32(metadata.storageItems) > high(uint32)-2 or uint64(metadata.storageBytes) > high(uint64)-added:
      fail(AccumulationEffectError.InvalidState) # Prove both serialized counter additions before forming them.
    metadata.storageItems = AccountStorageItems(uint32(metadata.storageItems)+2)
    metadata.storageBytes = AccountStorageBytes(uint64(metadata.storageBytes)+added)
  if not funded(metadata, parameters):
    fail(AccumulationEffectError.StorageFull) # FULL applies even to a restoration whose footprint did not change.
  let request = serviceRequestEntry(target, hash, length, history,
    RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
        3), maxBytes: ByteLimit(13))))
  if request.error != RequestError.None:
    fail(AccumulationEffectError.BackendFailure) # No failed canonical namespace key can be published.
  var writes = @[StateWrite(key: request.value.key, kind: StateWriteKind.Put,
      value: request.value.value)]
  if fresh:
    let encoded = serviceMetadataEntry(target, metadata, ByteLimit(ServiceMetadataBytes)).value
    writes.add(StateWrite(key: accountKey, kind: StateWriteKind.Put,
        value: encoded.value)) # Only creation changes metadata; restoration needs one write.
  var keys = previous.accountKeys
  if uint32(target) == uint32(self):
    let traced = prepareSelfAccountKeys(previous, writes)
    if traced.error != AccumulationEffectError.None:
      fail(traced.error) # Self-key capacity precedes candidate hashing.
    keys = traced.value # Foreign request keys never enter the self-key proof.

  let modified = prepareModifiedAccounts(previous, [target])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, target, writes)
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply(writes)
  case changed.error
  of StateStoreError.None:
    discard # One fully Merklized commit binds the new history to its exact prospective footprint.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Local store capacity never impersonates protocol FULL.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Previous accounts and request histories survive failed hashing.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial successor escapes other complete-map invariants.
  let candidate = if uint32(target) == uint32(self):
    selfAccountData(previous, changed.value, keys)
  else:
    successorData(previous, changed.value) # Foreign execution awaits parallel modified-account selection.
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
        exceptional: data.exceptional)))

proc recordAccumulationSolicit*(effects: AccumulationEffects, hash: ServicePreimageHash,
    length: RequestLength, parameters: Parameters): AccumulationEffectResult[AccumulationEffects] =
  ## Preserve self-only callers through the same bounded canonical target operation.
  let data = effects.data
  if data == nil:
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized) # Defaults own no invoker identity.
  let current = data.regular.data
  assert current != nil # Private pairs retain initialized dimensions.
  recordAccumulationSolicit(effects, hash, length, parameters,
      current.initial.contextInfo.value.service)

proc recordAccumulationForget*(effects: AccumulationEffects, hash: ServicePreimageHash,
    length: RequestLength, parameters: Parameters, target: ServiceIndex): AccumulationEffectResult[
        AccumulationEffects] =
  ## Forget the exact self/supervised request using invocation time; NotRequested is HUH for missing or insufficiently aged histories.
  ## Current Omega_F removes empty requests immediately, without deleting their preimage. No funding check or balance debit applies.
  ## Replacement needs one write; removal atomically updates footprint and deletes request/preimage in at most three writes.
  # No partial history, footprint or account successor escapes any refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Defaults supply no account or invocation provenance.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Expunge age requires genuine validated parameters.
  let previous = data.regular.data
  assert previous != nil # Published pairs retain initialized current contexts.
  if uint32(length) >= high(uint32)-1:
    fail(AccumulationEffectError.InvalidLength) # Current length HUH precedes all target/history work.
  let self = previous.initial.contextInfo.value.service
  let selected = authorizedAccountMetadata(previous, target)
  if selected.error != AccumulationEffectError.None:
    fail(selected.error) # WHO and authority HUH precede request namespace hashing.
  let prior = data.regular.effectServiceRequestHistory(target, hash, length)
  if prior.error != AccumulationEffectError.None:
    fail(prior.error) # Preserve HUH absence, malformed canonical state and namespace backend failures.
  let time = uint32(previous.initial.contextInvocation.value.bootstrapInfo.value.slot)
  let history = prior.value
  var replacement = requestedHistory()
  var remove = false
  var removePreimage = false
  case history.state
  of RequestState.Requested:
    remove = true # The current empty-history row removes only the request; no preimage deletion is implied.
  of RequestState.Available:
    replacement = unavailableHistory(history.since, RequestSlot(
        time)) # One slot always appends actual invocation time, with no age/funding condition.
  of RequestState.Unavailable:
    if uint64(uint32(history.unavailableFrom))+parameters.get(maxLookupAnchorAge)+4800 >= uint64(time):
      fail(AccumulationEffectError.NotRequested) # Strict widened expiry also handles nonpositive cutoffs without underflow.
    remove = true
    removePreimage = true # Only the expired two-slot row removes the retained preimage as well.
  of RequestState.Reavailable:
    if uint64(uint32(history.removedAt))+parameters.get(maxLookupAnchorAge)+4800 >= uint64(time):
      fail(AccumulationEffectError.NotRequested) # Expiry uses the second slot, never the later restoration time.
    replacement = unavailableHistory(history.restoredAt, RequestSlot(
        time)) # Retain latest availability and append current removal time.
  var writes: seq[StateWrite] = @[]
  if remove:
    let accountKey = chapterServiceKey(StateChapter(255), target)
    var metadata = selected.value
    let removed = 81'u64+uint64(uint32(length)) # Complete E4 length plus fixed overhead fits below 2^33.
    if uint32(metadata.storageItems) < 2 or uint64(metadata.storageBytes) < removed:
      fail(AccumulationEffectError.MalformedState) # Inconsistent stored counters cannot underflow into a fabricated footprint.
    metadata.storageItems = AccountStorageItems(uint32(metadata.storageItems)-2)
    metadata.storageBytes = AccountStorageBytes(uint64(metadata.storageBytes)-removed)
    let encoded = serviceMetadataEntry(target, metadata, ByteLimit(ServiceMetadataBytes)).value
    let request = serviceRequestKey(target, hash, length, ByteLimit(32))
    if request.error != RequestError.None:
      fail(AccumulationEffectError.BackendFailure) # Stop on failed request derivation without more namespace work.
    writes.add(StateWrite(key: accountKey, kind: StateWriteKind.Put, value: encoded.value))
    writes.add(StateWrite(key: request.value, kind: StateWriteKind.Delete))
    if removePreimage:
      let preimage = servicePreimageKey(target, hash, ByteLimit(32))
      if preimage.error != ServiceValueError.None:
        fail(AccumulationEffectError.BackendFailure) # Failed derivation leaves every original component intact.
      if array[31, byte](request.value) != array[31, byte](preimage.value):
        writes.add(StateWrite(key: preimage.value,
            kind: StateWriteKind.Delete)) # Avoid duplicate physical deletion descriptors.
  else:
    let request = serviceRequestEntry(target, hash, length, replacement,
      RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
          3), maxBytes: ByteLimit(13))))
    if request.error != RequestError.None:
      fail(AccumulationEffectError.BackendFailure) # Failed canonical replacement has no request payload to publish.
    writes.add(StateWrite(key: request.value.key, kind: StateWriteKind.Put,
        value: request.value.value)) # Replacement changes no metadata or preimage.
  var keys = previous.accountKeys
  if uint32(target) == uint32(self):
    let traced = prepareSelfAccountKeys(previous, writes)
    if traced.error != AccumulationEffectError.None:
      fail(traced.error) # Self-key capacity precedes candidate hashing.
    keys = traced.value # Foreign request keys never enter the self-key proof.

  let modified = prepareModifiedAccounts(previous, [target])
  if modified.error != AccumulationEffectError.None:
    fail(modified.error) # Complete membership capacity precedes candidate account publication.
  let facts = prepareAccountWriteFacts(previous, target, writes)
  if facts.error != AccumulationEffectError.None:
    fail(facts.error) # All successful write facts fit before candidate account publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply(writes)
  case changed.error
  of StateStoreError.None:
    discard # History, metadata and removed preimage are one complete immutable successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited store policy is separate from protocol HUH.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Previous maps survive even late candidate hashing failure.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial effects escape other store invariants.
  let candidate = if uint32(target) == uint32(self):
    selfAccountData(previous, changed.value, keys)
  else:
    successorData(previous, changed.value) # Foreign execution awaits parallel modified-account selection.
  candidate.writeFacts = facts.value # Bind physical keys to the same immutable account successor.
  candidate.modified = modified.value # Publish exactly the set paired with this successful account operation.
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
        exceptional: data.exceptional)))
proc recordAccumulationForget*(effects: AccumulationEffects, hash: ServicePreimageHash,
    length: RequestLength, parameters: Parameters): AccumulationEffectResult[AccumulationEffects] =
  ## Preserve self-only callers through the same bounded canonical target operation.
  let data = effects.data
  if data == nil:
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized) # Defaults own no invoker identity.
  let current = data.regular.data
  assert current != nil # Private pairs retain initialized dimensions.
  recordAccumulationForget(effects, hash, length, parameters,
      current.initial.contextInfo.value.service)
