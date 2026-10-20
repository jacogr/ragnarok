# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Locked two-slot full-state recovery follows one checksummed local selector and independent caller trust.
## Synchronous host-thread calls retain no canonical state graph between operations.

import std/posix/posix
import ../lib/[atomic_file, atomic_file_writer]
import ../codec/[bounded, state_trie]
import ./[checkpoint_head, checkpoint, checkpoint_transfer, store]

type
  CheckpointBank* = object ## Own the head lock and copied slot prefix; no raw child or destination escapes.
    selector: AtomicFileWriter
    prefix: string
  CheckpointBankError* {.pure.} = enum ## Only complete head-selected and trusted restoration exposes state.
    Uninitialized, None, InvalidPath, IoFailure, LimitExceeded, Busy, PublishedUnsynced,
      InvalidHead, InvalidCheckpoint, RootMismatch, AlreadyInitialized, StagedUnsynced, StaleHead
  CheckpointBankResult*[T] = object ## Format reasons occupy only their matching failed alternatives.
    case status: CheckpointBankError
    of None:
      completed: T
    of InvalidHead:
      headReason: CheckpointHeadError
    of InvalidCheckpoint:
      stateReason: CheckpointError
    else:
      discard # Native/default/trust refusals carry no candidate state or successful metadata.

proc `=copy`*(destination: var CheckpointBank, source: CheckpointBank) {.error.}
  ## A composite bank independently rejects duplicated lock retirement obligations.
proc `=dup`*(source: CheckpointBank): CheckpointBank {.error.}
  ## Actual ARC lowering must reject bank duplication even with a noncopyable child.
proc `=destroy`*(bank: CheckpointBank) =
  ## Explicit close is checked by the native owner before both managed paths retire.
  `=destroy`(bank.selector)
  `=destroy`(bank.prefix)
func opened*(bank: CheckpointBank): bool =
  ## Observe lifecycle without exposing slot paths or the locking descriptor.
  bank.selector.opened
func error*[T](outcome: CheckpointBankResult[T]): CheckpointBankError =
  ## Inspect the outer refusal without extracting state or a mismatched inner reason.
  outcome.status
func value*[T](outcome: CheckpointBankResult[T]): T {.inline,
    requires: outcome.status == CheckpointBankError.None.} =
  ## Only fully validated selection/restoration authorizes a returned payload.
  outcome.completed
func headError*[T](outcome: CheckpointBankResult[T]): CheckpointHeadError {.requires:
    outcome.status == CheckpointBankError.InvalidHead.} =
  ## Native, state and trust failures have no head-decoder diagnostic.
  outcome.headReason
func checkpointError*[T](outcome: CheckpointBankResult[T]): CheckpointError {.requires:
    outcome.status == CheckpointBankError.InvalidCheckpoint.} =
  ## Retain the exact selected-file decoder refusal without exposing its candidate.
  outcome.stateReason
func bankError(reason: AtomicFileError): CheckpointBankError =
  ## Exhaustive mapping preserves uncertainty and default lifecycle rather than granting success.
  case reason
  of AtomicFileError.None: CheckpointBankError.None # Completed native operations alone become None.
  of AtomicFileError.Uninitialized: CheckpointBankError.Uninitialized # Inactive owners cannot perform I/O.
  of AtomicFileError.InvalidPath: CheckpointBankError.InvalidPath # Preserve exact path admission failures.
  of AtomicFileError.IoFailure: CheckpointBankError.IoFailure # Filesystem errors cannot authorize fallback.
  of AtomicFileError.LimitExceeded: CheckpointBankError.LimitExceeded # No bounded-read prefix is exposed.
  of AtomicFileError.Busy: CheckpointBankError.Busy # Cooperating namespace contention remains nonblocking.
  of AtomicFileError.PublishedUnsynced: CheckpointBankError.PublishedUnsynced # Visibility is not confirmed durability.
proc openCheckpointBank*(bank: var CheckpointBank, prefix: string): CheckpointBankError =
  ## Lock prefix.head.lock before retaining independently owned slot-path bytes.
  if bank.opened: return CheckpointBankError.Busy # Live owners cannot change their namespace.
  if prefix.len == 0 or prefix.len > high(int) - 32:
    return CheckpointBankError.InvalidPath # Prove both head and raw helper suffix arithmetic before allocation.
  for character in prefix:
    if character == char(0): return CheckpointBankError.InvalidPath # No C path truncation may change identity.
  let acquired = bank.selector.openAtomicFileWriter(prefix & ".head")
  if acquired != AtomicFileError.None: return bankError(
      acquired) # Failed acquisition retains no path or lock ownership.
  bank.prefix = ""
  for character in prefix:
    bank.prefix.add(character) # Caller mutation cannot redirect later slot reads.
  CheckpointBankError.None
proc close*(bank: var CheckpointBank): CheckpointBankError =
  ## Disarm the native owner once and retain the stable lock inode for future contenders.
  bank.prefix = ""
  bankError(bank.selector.close())
proc selectedHead*(bank: var CheckpointBank): CheckpointBankResult[CheckpointHead] =
  ## Inspect exactly one bounded head while holding its namespace lock; this does not authenticate its root.
  let bytes = bank.selector.read(ByteLimit(CheckpointHeadBytes))
  if bytes.error != AtomicFileError.None:
    return CheckpointBankResult[CheckpointHead](status: bankError(
        bytes.error)) # Missing/corrupt head never selects an orphan slot.
  let decoded = decodeCheckpointHead(bytes.value, ByteLimit(CheckpointHeadBytes))
  if decoded.error != CheckpointHeadError.None:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
        headReason: decoded.error)
  CheckpointBankResult[CheckpointHead](status: CheckpointBankError.None, completed: decoded.value)
proc slotPath(bank: CheckpointBank, slot: CheckpointSlot): string =
  ## Only the validated selector can choose one of two fixed sibling names.
  if slot == CheckpointSlot.First: bank.prefix & ".0" # First generation's complete-map file.
  else: bank.prefix & ".1" # The only other canonical slot; temporary filenames are never considered.
proc restoreSelected(bank: var CheckpointBank, head: CheckpointHead, expected: StateRoot,
    limits: StateStoreLimits, limit: ByteLimit): CheckpointBankResult[StateStore] =
  ## Verify exactly the captured selector and its one complete map; this helper never scans or rereads a selector.
  if array[32, byte](head.root) != array[32, byte](expected):
    return CheckpointBankResult[StateStore](status: CheckpointBankError.RootMismatch) # A valid untrusted head cannot choose caller authority.
  let bytes = readBoundedFile(bank.slotPath(head.slot), limit)
  if bytes.error != AtomicFileError.None:
    return CheckpointBankResult[StateStore](status: bankError(
        bytes.error)) # Another intact slot cannot repair the selected generation implicitly.
  let restored = decodeFullCheckpoint(bytes.value, expected, limits, limit)
  if restored.error != CheckpointError.None:
    return CheckpointBankResult[StateStore](status: CheckpointBankError.InvalidCheckpoint,
        stateReason: restored.error)
  CheckpointBankResult[StateStore](status: CheckpointBankError.None, completed: restored.value)

proc restore*(bank: var CheckpointBank, expected: StateRoot, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointBankResult[StateStore] =
  ## Fail closed through head selection, independent trust, exact slot I/O and complete-map root verification.
  let selection = bank.selectedHead()
  if selection.error == CheckpointBankError.InvalidHead:
    return CheckpointBankResult[StateStore](status: CheckpointBankError.InvalidHead,
        headReason: selection.headError)
  if selection.error != CheckpointBankError.None:
    return CheckpointBankResult[StateStore](status: selection.error) # No head means no fallback scan.
  bank.restoreSelected(selection.value, expected, limits, limit)

proc verify*(bank: var CheckpointBank, expected: StateRoot, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointBankResult[CheckpointHead] =
  ## Verify selected state against independent caller trust, retiring the complete temporary graph before returning scalar metadata.
  let selection = bank.selectedHead()
  if selection.error == CheckpointBankError.InvalidHead:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
      headReason: selection.headError) # Format evidence belongs only to its matching failure alternative.
  if selection.error != CheckpointBankError.None:
    return CheckpointBankResult[CheckpointHead](status: selection.error) # No metadata is granted for absent or inaccessible selectors.
  let restored = bank.restoreSelected(selection.value, expected, limits, limit)
  if restored.error == CheckpointBankError.InvalidCheckpoint:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidCheckpoint,
      stateReason: restored.checkpointError) # Preserve exact decoder/root/resource failures without exposing a map.
  if restored.error != CheckpointBankError.None:
    return CheckpointBankResult[CheckpointHead](status: restored.error) # Wrong trust, I/O and ceilings remain payload-free.
  CheckpointBankResult[CheckpointHead](status: CheckpointBankError.None,
    completed: selection.value)

proc initialize*(bank: var CheckpointBank, prepared: PreparedCheckpoint,
    limit: ByteLimit): CheckpointBankResult[CheckpointHead] =
  ## Explicitly bootstrap an absent selector: durably stage slot zero before publishing generation zero.
  if not bank.opened: return default(CheckpointBankResult[
      CheckpointHead]) # Inactive resources cannot touch the namespace.
  if prepared.error != CheckpointError.None:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidCheckpoint,
        stateReason: prepared.error) # Validate all complete-map bytes before writing any file.
  if uint64(prepared.byteLength) > uint64(limit):
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidCheckpoint,
      stateReason: CheckpointError.LimitExceeded) # A narrower publication ceiling cannot authorize I/O for already prepared bytes.
  var headPath = bank.prefix & ".head"
  var metadata = default(Stat)
  if posix.lstat(headPath.toCString(), metadata) == 0:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.AlreadyInitialized) # Existing valid, malformed, directory or dangling-link selectors cannot be replaced by bootstrap.
  if posix.errno() != ENOENT:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.IoFailure) # Only true absence authorizes a new selector, never an unknown native failure.
  let head = newCheckpointHead(CheckpointGeneration(0), CheckpointSlot.First,
      prepared.root)
  let selection = encodeCheckpointHead(head, ByteLimit(CheckpointHeadBytes))
  if selection.error != CheckpointHeadError.None:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
        headReason: selection.error) # Backend failure cannot leave a newly staged slot.
  let staged = prepared.publish(bank.slotPath(CheckpointSlot.First), limit)
  if staged == AtomicFileError.PublishedUnsynced:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.StagedUnsynced) # A possibly durable orphan is not a committed selector and cannot authorize success.
  if staged != AtomicFileError.None:
    return CheckpointBankResult[CheckpointHead](status: bankError(
        staged)) # Pre-selector failure leaves no selected generation.
  let committed = bank.selector.replace(selection.value, ByteLimit(CheckpointHeadBytes))
  if committed != AtomicFileError.None:
    return CheckpointBankResult[CheckpointHead](status: bankError(
        committed)) # PublishedUnsynced remains distinct from staging uncertainty and successful adoption.
  CheckpointBankResult[CheckpointHead](status: CheckpointBankError.None, completed: head)

proc advance*(bank: var CheckpointBank, expected: CheckpointHead,
    prepared: PreparedCheckpoint, limit: ByteLimit): CheckpointBankResult[CheckpointHead] =
  ## Compare the exact expected selector, anchor its durability, then stage the inactive slot and publish its successor.
  if not bank.opened: return default(CheckpointBankResult[
      CheckpointHead]) # An inactive namespace authorizes no operation.
  if not expected.ready:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
        headReason: CheckpointHeadError.Uninitialized)
  if prepared.error != CheckpointError.None:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidCheckpoint,
        stateReason: prepared.error) # Preflight the complete candidate before any write.
  if uint64(prepared.byteLength) > uint64(limit):
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidCheckpoint,
      stateReason: CheckpointError.LimitExceeded) # A narrower publication ceiling cannot authorize I/O for already prepared bytes.
  let selected = bank.selectedHead()
  if selected.error == CheckpointBankError.InvalidHead:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
        headReason: selected.headError)
  if selected.error != CheckpointBankError.None:
    return CheckpointBankResult[CheckpointHead](status: selected.error) # No missing/corrupt head can authorize implicit bootstrap.
  let current = selected.value
  if uint64(current.generation) != uint64(expected.generation) or current.slot != expected.slot or
      array[32, byte](current.root) != array[32, byte](expected.root):
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.StaleHead) # Every selector field participates in the local compare-and-publish contract.
  let successor = nextCheckpointHead(current, prepared.root)
  if successor.error != CheckpointHeadError.None:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
        headReason: successor.error) # Exhaustion cannot wrap or overwrite an inactive slot.
  let head = successor.value
  let metadata = encodeCheckpointHead(head, ByteLimit(CheckpointHeadBytes))
  if metadata.error != CheckpointHeadError.None:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
        headReason: metadata.error)
  let anchored = bank.selector.synchronize()
  if anchored != AtomicFileError.None:
    return CheckpointBankResult[CheckpointHead](status: bankError(
        anchored)) # An older durable head must not reference data about to be overwritten after startup/uncertain publication.
  let staged = prepared.publish(bank.slotPath(head.slot), limit)
  if staged == AtomicFileError.PublishedUnsynced:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.StagedUnsynced) # The old selector remains selected; uncertain inactive data is not a committed head.
  if staged != AtomicFileError.None:
    return CheckpointBankResult[CheckpointHead](status: bankError(
        staged)) # Pre-selector failure preserves the selected generation.
  let committed = bank.selector.replace(metadata.value, ByteLimit(CheckpointHeadBytes))
  if committed != AtomicFileError.None:
    return CheckpointBankResult[CheckpointHead](status: bankError(
        committed)) # A visible-but-unsynced selector has no successful adoption payload.
  CheckpointBankResult[CheckpointHead](status: CheckpointBankError.None, completed: head)

proc initialize*(bank: var CheckpointBank, snapshot: StateStoreSnapshot,
    limit: ByteLimit): CheckpointBankResult[CheckpointHead] =
  ## Synchronous compatibility wrapper prepares independent bytes before the shared ordered bootstrap boundary.
  if not bank.opened: return default(CheckpointBankResult[
      CheckpointHead]) # Preserve inactive-owner refusal before source computation.
  let prepared = prepareFullCheckpoint(snapshot, limit)
  bank.initialize(prepared, limit)
proc advance*(bank: var CheckpointBank, expected: CheckpointHead,
    snapshot: StateStoreSnapshot, limit: ByteLimit): CheckpointBankResult[CheckpointHead] =
  ## Existing snapshot callers retain exact refusal ordering while all publication shares detached-buffer code.
  if not bank.opened: return default(CheckpointBankResult[
      CheckpointHead]) # Closed resources cannot serialize a candidate.
  if not expected.ready:
    return CheckpointBankResult[CheckpointHead](status: CheckpointBankError.InvalidHead,
      headReason: CheckpointHeadError.Uninitialized) # Default expectation remains a head failure before snapshot preparation.
  let prepared = prepareFullCheckpoint(snapshot, limit)
  bank.advance(expected, prepared, limit)
