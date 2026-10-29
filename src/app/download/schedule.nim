# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded peer rotation for one-child downloads. The host supplies authenticated peer identities,
## retires native callbacks before finishing attempts, and reports adoption outside callbacks.

import std/assertions
import ../../codec/bounded

type
  DownloadPeerId* = distinct uint64 ## Nonzero local authenticated-peer identity, never a remote block claim.
  DownloadScheduleTick* = distinct uint64 ## Host monotonic milliseconds; unrelated to protocol slots.
  DownloadRetryDelay* = distinct uint64 ## Explicit positive per-peer cooldown in milliseconds.
  DownloadScheduleLimits* = object ## One plan has bounded peers and attempts, with no inferred retry budget.
    peers*: ElementLimit
    attempts*: uint64
    retryDelay*: DownloadRetryDelay
  DownloadScheduleError* {.pure.} = enum ## Refusals expose no selected peer or usable attempt certificate.
    Uninitialized, None, Busy, InvalidPolicy, LimitExceeded, InvalidPeer, DuplicatePeer,
    Waiting, Exhausted, Completed, ClockRegression, StaleAttempt
  DownloadAttemptOutcome* {.pure.} = enum ## Empty is a retryable observation; only actual canonical adoption completes a plan.
    Retry, Empty, Adopted
  AttemptOwner = ref object ## Immutable certificate identity prevents cross-plan/old-attempt acknowledgement.
    peer: DownloadPeerId
  DownloadAttempt* = object ## Copyable immutable lease; its private identity is valid for exactly one selection.
    owner: nil AttemptOwner
  DownloadSelection* = object ## Private discriminator guards the only successful attempt payload.
    case status: DownloadScheduleError
    of None:
      selected: DownloadAttempt
    else:
      discard                 # Waiting/budget/default refusals contain reasons alone.
  PeerState = object ## Cooldown begins when the host retires an attempt, rather than when it starts.
    peer: DownloadPeerId
    finished: uint64
    cooling: bool
  DownloadSchedule* = object ## Exclusive mutable plan; no native handles, wire bytes, headers or state maps are retained.
    peers: seq[PeerState]
    active: nil AttemptOwner
    limits: DownloadScheduleLimits
    cursor: int
    used, lastTick: uint64
    initialized, completed: bool

proc `=copy`*(destination: var DownloadSchedule, source: DownloadSchedule) {.
    error: "DownloadSchedule owns attempt selection".}
  ## A copied plan could authorize duplicate attempts against the same host peer set.
proc `=dup`*(source: DownloadSchedule): DownloadSchedule {.error.}
  ## Retaining a schedule requires its original owner; immutable attempt certificates remain copyable.
proc `==`*(left, right: DownloadPeerId): bool {.borrow.}
  ## Local peer identities occupy their own domain.

func error*(selection: DownloadSelection): DownloadScheduleError =
  ## Defaults/refusals do not authorize opening a native stream.
  selection.status
func value*(selection: DownloadSelection): DownloadAttempt {.inline,
    requires: selection.status == DownloadScheduleError.None.} =
  ## Extract only a successful lease, never a waiting or failed selection.
  selection.selected
func valid*(attempt: DownloadAttempt): bool =
  ## An absent lease never identifies an active attempt.
  attempt.owner != nil
proc peer*(attempt: DownloadAttempt): DownloadPeerId {.inline, requires: attempt.owner != nil.} =
  ## Read the immutable selected peer, without granting acknowledgement authority to an integer.
  let owner = attempt.owner
  if owner != nil:
    owner.peer # Freeze and narrow the certificate borrow for the pinned compiler.
  else:
    assert false, "absent download attempt" # Preserve guarded extraction even without caller contract inference.
    DownloadPeerId(0)
func busy*(schedule: DownloadSchedule): bool =
  ## The host holds this lease through native teardown, preparation backpressure and adoption.
  schedule.active != nil

proc configure*(schedule: var DownloadSchedule, peers: openArray[DownloadPeerId],
    limits: DownloadScheduleLimits, now: DownloadScheduleTick): DownloadScheduleError =
  ## Atomically replace an idle plan with an explicit caller-authorized session list and fresh budget.
  if schedule.busy: return DownloadScheduleError.Busy # Reconfiguration cannot orphan callbacks or active preparation.
  if uint64(limits.peers) == 0 or uint64(limits.peers) > 64 or limits.attempts == 0 or
      uint64(limits.retryDelay) == 0:
    return DownloadScheduleError.InvalidPolicy # A hard 64-session cap bounds duplicate checking and every selection scan.
  if peers.len == 0 or uint64(peers.len) > uint64(limits.peers):
    return DownloadScheduleError.LimitExceeded # Prove bounded allocation before copying caller storage.
  for index, peer in peers:
    if uint64(peer) == 0: return DownloadScheduleError.InvalidPeer # Zero never identifies a authenticated host peer.
    for previous in 0..<index:
      if peers[previous] == peer: return DownloadScheduleError.DuplicatePeer # Duplicate weights cannot bypass a peer's cooldown.
  if schedule.initialized and uint64(now) < schedule.lastTick:
    return DownloadScheduleError.ClockRegression # Reconfiguration does not reset the monotonic-clock contract.
  var retained = newSeq[PeerState](peers.len)
  for index, peer in peers:
    retained[index] = PeerState(peer: peer, finished: 0,
        cooling: false) # Every new plan starts with eligible peers.
  schedule = DownloadSchedule(peers: retained, limits: limits, cursor: 0, used: 0,
    lastTick: uint64(now), initialized: true, completed: false)
  DownloadScheduleError.None

proc select*(schedule: var DownloadSchedule, now: DownloadScheduleTick): DownloadSelection =
  ## Inspect at most the retained peer count and reserve one immutable lease before any host I/O.
  if not schedule.initialized: return DownloadSelection(status: DownloadScheduleError.Uninitialized)
  if schedule.busy: return DownloadSelection(status: DownloadScheduleError.Busy)
  if uint64(now) < schedule.lastTick: return DownloadSelection(
      status: DownloadScheduleError.ClockRegression)
  if schedule.completed: return DownloadSelection(status: DownloadScheduleError.Completed)
  if schedule.used == schedule.limits.attempts:
    return DownloadSelection(status: DownloadScheduleError.Exhausted) # Checked before increment, including the uint64 maximum.
  schedule.lastTick = uint64(now)
  var index = schedule.cursor
  for scanned in 0..<schedule.peers.len:
    let peer = schedule.peers[index]
    if not peer.cooling or uint64(now) - peer.finished >= uint64(schedule.limits.retryDelay):
      let owner = AttemptOwner(peer: peer.peer)
      schedule.active = owner
      inc schedule.used # The explicit attempt ceiling proves this cannot wrap.
      schedule.cursor = index + 1 # At most 64, independently of host integer width.
      if schedule.cursor == schedule.peers.len: schedule.cursor = 0 # Round-robin selection includes eligible skipped peers on later scans.
      return DownloadSelection(status: DownloadScheduleError.None,
        selected: DownloadAttempt(owner: owner))
    inc index
    if index == schedule.peers.len: index = 0 # One bounded wrap; no unbounded polling or clock advancement.
  DownloadSelection(status: DownloadScheduleError.Waiting)

proc finish*(schedule: var DownloadSchedule, attempt: DownloadAttempt,
    outcome: DownloadAttemptOutcome, now: DownloadScheduleTick): DownloadScheduleError =
  ## Host calls after native close and terminal producer/adoption work; stale leases cannot retire replacements.
  let owner = attempt.owner
  if owner == nil or schedule.active == nil or schedule.active != owner:
    return DownloadScheduleError.StaleAttempt # Exact certificate identity also rejects another scheduler's equal peer ID.
  if uint64(now) < schedule.lastTick:
    return DownloadScheduleError.ClockRegression # Keep the lease active so a valid clock observation can retry acknowledgement.
  schedule.lastTick = uint64(now)
  for index in 0..<schedule.peers.len:
    if schedule.peers[index].peer == owner.peer:
      schedule.peers[index].finished = uint64(now)
      schedule.peers[index].cooling = true # Subtraction in select avoids deadline-addition overflow.
  schedule.completed = outcome == DownloadAttemptOutcome.Adopted
  schedule.active = nil # Empty, network failure and producer refusal all release the single-attempt slot.
  DownloadScheduleError.None
