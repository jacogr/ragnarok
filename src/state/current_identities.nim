# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind an original selected complete logical parent to a genuine update with unchanged physical namespace identities.
## This observation is not a producer mutation/event certificate, payload validity or installation authority.
import ./parent_logical as state_parent_logical
import ./parent_globals as state_parent_globals
import ./parent_profile as state_parent_profile
import ./supplied_logical_inventory as state_supplied_logical_inventory
import ./inventory as state_inventory
import ./manifest as state_manifest
import ./store as state_store
import ./accumulation_current_update as state_accumulation_current_update
import ./current_logical as state_current_logical
import ./current_state as state_current_state
import ./current_globals as state_current_globals
import ./current_profile as state_current_profile
import ../chain/provider as chain_provider
import ../chain/genesis as chain_genesis
import ../chain/parameters as chain_parameters
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
type
  CurrentIdentityLimits* = object ## Full prior/posterior view copies and sorted key inspections require independent upfront admission.
    blocks*, keys*: ElementLimit
    viewBytes*: ByteLimit
  CurrentIdentityInfo* = object ## Fixed copied accounting grants no permission to replace original owners or policies.
    entries*: int
    keyChecks*, viewBytes*: uint64
  IdentityOrigin {.pure.} = enum ## Private source selection cannot be retagged by callers or inferred from equal roots.
    Configured, Completed
  PreservedCurrentIdentities* = object ## Only exact original state/view/profile and unchanged complete keys construct this private certificate.
    initialized: bool
    parent: SelectedLogicalParent
    prior: CurrentLogicalState
    logical: SuppliedLogicalInventory
    origin: IdentityOrigin
    update: PreparedCurrentChainUpdate
    info: CurrentIdentityInfo
  IdentitySource = object ## Fixed private original owners/context/retention facts carry no externally replaceable view or Parameters.
    origin: IdentityOrigin
    parent: SelectedLogicalParent
    prior: CurrentLogicalState
    logical: SuppliedLogicalInventory
    context: BlockSnapshotContext
    viewInfo: ChainViewRetentionInfo
  CurrentIdentityError* {.pure.} = enum ## New/missing identities remain explicit unsupported changes, distinct from bad provenance and resources.
    Uninitialized, None, InvalidParent, InvalidUpdate, LimitExceeded, ParentMismatch, ViewMismatch,
      ParametersMismatch, MissingIdentity, NewIdentity, WrongSource
  CurrentIdentityResult*[T] = object ## Failed identity observations contain only fixed reasons and optional first refused physical key.
    case status: CurrentIdentityError
    of None:
      completed: T
    of MissingIdentity, NewIdentity:
      identity: StateKey
    else:
      discard # No failed/default identity result carries executable continuation evidence.
func error*[T](outcome: CurrentIdentityResult[T]): CurrentIdentityError =
  ## Read selected immutable stage without retagging or constructing a successful owner.
  outcome.status
func value*[T](outcome: CurrentIdentityResult[T]): T {.inline, requires: outcome.status ==
    CurrentIdentityError.None.} =
  ## Successful exact-original observations alone grant payload access.
  outcome.completed
func refusedIdentity*[T](outcome: CurrentIdentityResult[T]): StateKey {.inline,
    requires: outcome.status == CurrentIdentityError.MissingIdentity or outcome.status ==
    CurrentIdentityError.NewIdentity.} =
  ## Copy only the first actual missing/new complete-map identity, not a logical mutation event.
  outcome.identity
func compare(left, right: StateKey): int =
  ## Lexicographic order matches complete store key sorting without byte-array allocation.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for i in 0..<31:
    if a[i] < b[i]: return -1 # First differing octet fixes deterministic key order.
    if a[i] > b[i]: return 1
  0
proc preserveSource(source: IdentitySource, update: PreparedCurrentChainUpdate,
    limits: CurrentIdentityLimits): CurrentIdentityResult[PreservedCurrentIdentities] =
  ## Check exact private configured/completed original context and all view/key work before copying or traversal; no payload copy/hash occurs.
  template fail(reason: CurrentIdentityError) =
    return CurrentIdentityResult[PreservedCurrentIdentities](status: reason)
  let captured = source.logical.suppliedInventory
  if captured.error != SuppliedLogicalError.None: fail(CurrentIdentityError.InvalidParent)
  let original = source.context
  if not sameStateSnapshot(captured.value.inventorySource.value.manifestSource.value,
      original.state):
    fail(CurrentIdentityError.InvalidParent) # Both original logical and configured/completed producer observations must retain the exact same physical state.
  if not update.ready: fail(CurrentIdentityError.InvalidUpdate)
  if not sameStateSnapshot(original.state, update.currentUpdatePriorState):
    fail(CurrentIdentityError.ParentMismatch) # Equal roots on another immutable owner never qualify an original predecessor.
  let sourceInfo = source.viewInfo
  let prior = update.currentUpdatePriorViewInfo
  let posterior = update.currentUpdateViewInfo
  var available = min(uint64(limits.viewBytes), uint64(high(int)))
  let budget = available
  var blocks = uint64(limits.blocks)
  for info in [sourceInfo, prior, posterior]:
    if uint64(info.owners) > blocks or info.bytes > available:
      fail(CurrentIdentityError.LimitExceeded) # Whole retained view descriptors/indexes are admitted before any heavy getter.
    blocks-=uint64(info.owners)
    available-=info.bytes
  let successor = update.currentUpdateState
  let oldCount = original.state.commitment.entries
  let newCount = successor.commitment.entries
  var keys = uint64(limits.keys)
  if uint64(oldCount) > keys: fail(CurrentIdentityError.LimitExceeded)
  keys-=uint64(oldCount)
  if uint64(newCount) > keys: fail(CurrentIdentityError.LimitExceeded)
  keys-=uint64(newCount) # Both immutable array lengths prove native ordinal conversions and aggregate traversal before inspection.
  let originalView = if source.origin == IdentityOrigin.Configured:
    source.parent.logicalParentGlobals.value.parentGlobalsProfile.value.copyParentView(ByteLimit(
        sourceInfo.bytes)).value
  else:
    source.prior.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value.currentUpdateView # Cheap prior facts admitted the complete copied ordered history/finality before this getter.
  if not sameChainView(originalView, update.currentUpdatePriorView):
    fail(CurrentIdentityError.ViewMismatch) # Ordered history, complete Parameters and explicit finality/absence all bind the predecessor.
  let child = update.currentUpdateView.bestBlockContext
  if not sameParameterProfile(original.parameters, child.parameters):
    fail(CurrentIdentityError.ParametersMismatch) # Matching four cardinalities cannot replace the full execution/economic tuple.
  var i = 0
  var j = 0
  while i < oldCount and j < newCount:
    let left = original.state.keyAt(StateEntryIndex(i)).value
    let right = successor.keyAt(StateEntryIndex(j)).value
    let order = compare(left, right)
    if order < 0:
      return CurrentIdentityResult[PreservedCurrentIdentities](
          status: CurrentIdentityError.MissingIdentity, identity: left)
    if order > 0:
      return CurrentIdentityResult[PreservedCurrentIdentities](
          status: CurrentIdentityError.NewIdentity, identity: right)
    inc i
    inc j # Only fixed identical physical keys advance both sorted immutable observations.
  if i < oldCount:
    return CurrentIdentityResult[PreservedCurrentIdentities](
        status: CurrentIdentityError.MissingIdentity, identity: original.state.keyAt(
        StateEntryIndex(i)).value)
  if j < newCount:
    return CurrentIdentityResult[PreservedCurrentIdentities](
        status: CurrentIdentityError.NewIdentity, identity: successor.keyAt(StateEntryIndex(j)).value)
  CurrentIdentityResult[PreservedCurrentIdentities](status: CurrentIdentityError.None,
    completed: PreservedCurrentIdentities(initialized: true, parent: source.parent,
      prior: source.prior, logical: source.logical, origin: source.origin, update: update,
      info: CurrentIdentityInfo(entries: oldCount, keyChecks: uint64(limits.keys)-keys,
          viewBytes: budget-available)))
proc preserveCurrentIdentities*(parent: SelectedLogicalParent, update: PreparedCurrentChainUpdate,
    limits: CurrentIdentityLimits): CurrentIdentityResult[PreservedCurrentIdentities] =
  ## Configured startup source remains distinct from completed current provenance, sharing only the private fixed original comparison path.
  let selected = parent.logicalParentGlobals
  if selected.error != ParentLogicalError.None:
    return CurrentIdentityResult[PreservedCurrentIdentities](
        status: CurrentIdentityError.InvalidParent)
  let profile = selected.value.parentGlobalsProfile.value
  preserveSource(IdentitySource(origin: IdentityOrigin.Configured, parent: parent, prior: default(
      CurrentLogicalState), logical: parent.logicalParentInventory.value,
      context: profile.parentContext.value, viewInfo: profile.parentProfileInfo.value.view), update, limits)
proc preserveCurrentIdentities*(prior: CurrentLogicalState, update: PreparedCurrentChainUpdate,
    limits: CurrentIdentityLimits): CurrentIdentityResult[PreservedCurrentIdentities] =
  ## Only a genuinely fully matched prior current source supplies its actual successor snapshot/full view/Parameters; no fabricated startup update or detached map enters.
  template fail() =
    return CurrentIdentityResult[PreservedCurrentIdentities](
        status: CurrentIdentityError.InvalidParent)
  let logical = prior.currentLogicalInventory
  let current = prior.currentLogicalSource
  if logical.error != CurrentLogicalError.None or current.error != CurrentLogicalError.None: fail()
  let globals = current.value.currentStateGlobals
  if globals.error != CurrentStateError.None: fail()
  let profile = globals.value.qualifiedCurrentProfile
  if profile.error != CurrentGlobalsError.None: fail()
  let producer = profile.value.derivedUpdate
  if producer.error != CurrentProfileError.None or not producer.value.ready: fail()
  preserveSource(IdentitySource(origin: IdentityOrigin.Completed, parent: default(
      SelectedLogicalParent), prior: prior, logical: logical.value,
      context: producer.value.currentUpdateChildContext,
      viewInfo: producer.value.currentUpdateViewInfo), update, limits)
proc identityParent*(source: PreservedCurrentIdentities): CurrentIdentityResult[
    SelectedLogicalParent] =
  ## Retain only the exact original complete selected logical parent.
  if not source.initialized: return CurrentIdentityResult[SelectedLogicalParent](
      status: CurrentIdentityError.Uninitialized)
  if source.origin != IdentityOrigin.Configured: return CurrentIdentityResult[
      SelectedLogicalParent](status: CurrentIdentityError.WrongSource)
  CurrentIdentityResult[SelectedLogicalParent](status: CurrentIdentityError.None,
      completed: source.parent)
proc identityUpdate*(source: PreservedCurrentIdentities): CurrentIdentityResult[
    PreparedCurrentChainUpdate] =
  ## Retain genuine producer provenance without accepting replacement state/view/configuration inputs.
  if not source.initialized: return CurrentIdentityResult[PreparedCurrentChainUpdate](
      status: CurrentIdentityError.Uninitialized)
  CurrentIdentityResult[PreparedCurrentChainUpdate](status: CurrentIdentityError.None,
      completed: source.update)
proc identityInfo*(source: PreservedCurrentIdentities): CurrentIdentityResult[CurrentIdentityInfo] =
  ## Copy fixed successful observations while keeping sources and discriminators private.
  if not source.initialized: return CurrentIdentityResult[CurrentIdentityInfo](
      status: CurrentIdentityError.Uninitialized)
  CurrentIdentityResult[CurrentIdentityInfo](status: CurrentIdentityError.None,
      completed: source.info)
proc identityLogical*(source: PreservedCurrentIdentities): CurrentIdentityResult[
    SuppliedLogicalInventory] =
  ## Retain complete original logical identities/raw keys for bounded actual-successor refresh consumers.
  if not source.initialized: return CurrentIdentityResult[SuppliedLogicalInventory](
      status: CurrentIdentityError.Uninitialized)
  CurrentIdentityResult[SuppliedLogicalInventory](status: CurrentIdentityError.None,
      completed: source.logical)
proc identityPriorCurrent*(source: PreservedCurrentIdentities): CurrentIdentityResult[
    CurrentLogicalState] =
  ## Retain only genuine completed-origin parent provenance; configured startup sources refuse distinctly without a fake current owner.
  if not source.initialized: return CurrentIdentityResult[CurrentLogicalState](
      status: CurrentIdentityError.Uninitialized)
  if source.origin != IdentityOrigin.Completed: return CurrentIdentityResult[CurrentLogicalState](
      status: CurrentIdentityError.WrongSource)
  CurrentIdentityResult[CurrentLogicalState](status: CurrentIdentityError.None,
      completed: source.prior)
