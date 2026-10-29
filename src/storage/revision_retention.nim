# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded revision pins retain immutable read owners without choosing eviction or reclaiming disk.
## Catalog copies share immutable slots; releasing a pin affects only the selected catalog handle.
import std/assertions
import ./node/repository as node_repository
import ../codec/bounded

type
  RetentionError* {.pure.} = enum ## Refusals leave the selected catalog and every retained view unchanged.
    Uninitialized, None, InvalidView, InvalidToken, MissingToken, LimitExceeded
  RetentionResult*[T] = object ## Only success carries a token or immutable read view.
    case status: RetentionError
    of None: completed: T
    else: discard              # Default/refused results own no payload.
  RetainedSlot = ref object ## Identity distinguishes same-generation views from unrelated repositories.
    view: RepositoryView
  RetentionToken* = object ## Opaque acyclic pin identity, meaningful only while present in a catalog.
    slot: nil RetainedSlot
  RetentionData = ref object ## An immutable bounded table owns slots, never a back-reference to tokens/catalogs.
    slots: seq[RetainedSlot]
    limit: ElementLimit
  RevisionRetention* = object ## Independently updateable handle sharing only immutable catalog versions.
    head: nil RetentionData

func error*[T](outcome: RetentionResult[T]): RetentionError =
  ## Inspect a refusal without exposing any result storage.
  outcome.status
func value*[T](outcome: RetentionResult[T]): T {.requires: outcome.status == RetentionError.None.} =
  ## Extract only the selected successful result.
  outcome.completed
proc newRevisionRetention*(limit: ElementLimit): RevisionRetention =
  ## Open an empty bounded catalog; zero capacity is valid and admits no pins.
  RevisionRetention(head: RetentionData(limit: limit))
func opened*(catalog: RevisionRetention): bool =
  ## Query lifecycle without exposing catalog storage.
  catalog.head != nil
proc len*(catalog: RevisionRetention): int {.requires: catalog.head != nil.} =
  ## Count explicit pins, including repeated independent pins of the same view.
  let head = catalog.head
  assert head != nil
  head.slots.len
proc retain*(catalog: var RevisionRetention, view: RepositoryView): RetentionResult[
    RetentionToken] =
  ## Copy immutable owners into a fresh slot only after lifecycle, view and count checks.
  let head = catalog.head
  if head == nil: return RetentionResult[RetentionToken](status: RetentionError.Uninitialized)
  if not view.initialized: return RetentionResult[RetentionToken](
      status: RetentionError.InvalidView)
  if uint64(head.slots.len) >= uint64(head.limit) or head.slots.len == high(int):
    return RetentionResult[RetentionToken](status: RetentionError.LimitExceeded)
  let slot = RetainedSlot(view: view)
  var slots: seq[RetainedSlot] = @[]
  for i in 0..<head.slots.len: slots.add(head.slots[i]) # Copy slot owners; never mutate shared history.
  slots.add(slot)
  catalog.head = RetentionData(slots: slots, limit: head.limit)
  RetentionResult[RetentionToken](status: RetentionError.None, completed: RetentionToken(slot: slot))
proc lookup*(catalog: RevisionRetention, token: RetentionToken): RetentionResult[RepositoryView] =
  ## Require exact slot membership, never a forgeable ordinal or generation-only match.
  let head = catalog.head
  if head == nil: return RetentionResult[RepositoryView](status: RetentionError.Uninitialized)
  let selected = token.slot
  if selected == nil: return RetentionResult[RepositoryView](status: RetentionError.InvalidToken)
  for i in 0..<head.slots.len:
    let slot = head.slots[i]
    if slot == selected:
      return RetentionResult[RepositoryView](status: RetentionError.None, completed: slot.view)
  RetentionResult[RepositoryView](status: RetentionError.MissingToken)
proc release*(catalog: var RevisionRetention, token: RetentionToken): RetentionError =
  ## Remove catalog ownership explicitly; caller-held tokens/views and copied catalogs survive.
  let head = catalog.head
  if head == nil: return RetentionError.Uninitialized
  let selected = token.slot
  if selected == nil: return RetentionError.InvalidToken
  var index = -1
  for i in 0..<head.slots.len:
    let slot = head.slots[i]
    if slot == selected:
      index = i
      break # Exact identity found; slot numbering carries no external meaning.
  if index < 0: return RetentionError.MissingToken
  var slots: seq[RetainedSlot] = @[]
  for i in 0..<head.slots.len:
    let slot = head.slots[i]
    if i != index:
      slots.add(slot)
  catalog.head = RetentionData(slots: slots, limit: head.limit)
  RetentionError.None
proc close*(catalog: var RevisionRetention): RetentionError =
  ## Drop this catalog's pins without revoking immutable readers or another copied handle.
  if catalog.head == nil: return RetentionError.Uninitialized
  catalog.head = nil
  RetentionError.None
