# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind an original selected complete logical parent to a genuine update with unchanged physical namespace identities.
## This observation is not a producer mutation/event certificate, payload validity or installation authority.
import ./[parent_logical, parent_globals, parent_profile, supplied_logical_inventory, inventory,
    manifest, store, accumulation_current_update]
import ../chain/[provider, genesis, parameters]
import ../codec/[bounded, state_layout]
type
  CurrentIdentityLimits* = object ## Full prior/posterior view copies and sorted key inspections require independent upfront admission.
    blocks*, keys*: ElementLimit
    viewBytes*: ByteLimit
  CurrentIdentityInfo* = object ## Fixed copied accounting grants no permission to replace original owners or policies.
    entries*: int
    keyChecks*, viewBytes*: uint64
  PreservedCurrentIdentities* = object ## Only exact original state/view/profile and unchanged complete keys construct this private certificate.
    initialized: bool
    parent: SelectedLogicalParent
    update: PreparedCurrentChainUpdate
    info: CurrentIdentityInfo
  CurrentIdentityError* {.pure.} = enum ## New/missing identities remain explicit unsupported changes, distinct from bad provenance and resources.
    Uninitialized, None, InvalidParent, InvalidUpdate, LimitExceeded, ParentMismatch, ViewMismatch,
      ParametersMismatch, MissingIdentity, NewIdentity
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
proc preserveCurrentIdentities*(parent: SelectedLogicalParent, update: PreparedCurrentChainUpdate,
    limits: CurrentIdentityLimits): CurrentIdentityResult[PreservedCurrentIdentities] =
  ## Check provenance and complete resource admission before view copies or bounded sorted key inspection; no hashes or payload copies.
  template fail(reason: CurrentIdentityError) =
    return CurrentIdentityResult[PreservedCurrentIdentities](status: reason)
  let selected = parent.logicalParentGlobals
  if selected.error != ParentLogicalError.None: fail(CurrentIdentityError.InvalidParent)
  if not update.ready: fail(CurrentIdentityError.InvalidUpdate)
  let profile = selected.value.parentGlobalsProfile.value
  let original = profile.parentContext.value
  if not sameStateSnapshot(original.state, update.currentUpdatePriorState):
    fail(CurrentIdentityError.ParentMismatch) # Equal roots on another immutable owner never qualify an original predecessor.
  let sourceInfo = profile.parentProfileInfo.value.view
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
  let originalView = profile.copyParentView(ByteLimit(sourceInfo.bytes)).value
  if not sameChainView(originalView, update.currentUpdatePriorView):
    fail(CurrentIdentityError.ViewMismatch) # Ordered history, complete Parameters and explicit finality/absence all bind the predecessor.
  let child = update.currentUpdateView.bestBlockContext
  if original.parameters.encodeParameters != child.parameters.encodeParameters:
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
    completed: PreservedCurrentIdentities(initialized: true, parent: parent, update: update,
      info: CurrentIdentityInfo(entries: oldCount, keyChecks: uint64(limits.keys)-keys,
          viewBytes: budget-available)))
proc identityParent*(source: PreservedCurrentIdentities): CurrentIdentityResult[
    SelectedLogicalParent] =
  ## Retain only the exact original complete selected logical parent.
  if not source.initialized: return CurrentIdentityResult[SelectedLogicalParent](
      status: CurrentIdentityError.Uninitialized)
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
      completed: source.parent.logicalParentInventory.value)
