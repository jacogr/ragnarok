# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_download_schedule_arc_release"}

## Deterministic peer selection, bounded retries, immutable attempt identity and ARC ownership.

import std/[assertions, syncio]
import ../../../src/app/download_schedule
import ../../../src/codec/bounded
import ../../support/arc_evidence

proc policy(attempts = 8'u64, delay = 10'u64): DownloadScheduleLimits =
  ## Every test chooses explicit count and timing ceilings.
  DownloadScheduleLimits(peers: ElementLimit(3), attempts: attempts,
    retryDelay: DownloadRetryDelay(delay))

proc take(schedule: var DownloadSchedule, now: uint64, expected: uint64): DownloadAttempt =
  ## Positive extraction witnesses the same guarded API used by the transport host.
  let chosen = schedule.select(DownloadScheduleTick(now))
  assert chosen.error == DownloadScheduleError.None
  result = chosen.value
  assert uint64(result.peer) == expected
  assert schedule.busy
  assert schedule.select(DownloadScheduleTick(now)).error == DownloadScheduleError.Busy

proc configuration() =
  ## Invalid configuration preserves a prior plan and copies no caller-owned peer array.
  var schedule = default(DownloadSchedule)
  assert schedule.select(DownloadScheduleTick(0)).error == DownloadScheduleError.Uninitialized
  assert not default(DownloadAttempt).valid
  var peers = @[DownloadPeerId(1), DownloadPeerId(2)]
  assert schedule.configure(peers, policy(), DownloadScheduleTick(10)) == DownloadScheduleError.None
  peers[0] = DownloadPeerId(99) # The configured immutable identities do not borrow this backing storage.
  assert schedule.configure([], policy(), DownloadScheduleTick(10)) ==
      DownloadScheduleError.LimitExceeded
  assert schedule.configure([DownloadPeerId(0)], policy(), DownloadScheduleTick(10)) ==
      DownloadScheduleError.InvalidPeer
  assert schedule.configure([DownloadPeerId(3), DownloadPeerId(3)], policy(),
    DownloadScheduleTick(10)) == DownloadScheduleError.DuplicatePeer
  var short = policy()
  short.peers = ElementLimit(1)
  assert schedule.configure(peers, short, DownloadScheduleTick(10)) ==
      DownloadScheduleError.LimitExceeded
  for bad in [0'u64, 65'u64, high(uint64)]:
    short.peers = ElementLimit(bad) # Validate policy widths before allocation/narrowing.
    assert schedule.configure(peers, short, DownloadScheduleTick(10)) ==
        DownloadScheduleError.InvalidPolicy
  short = policy(0)
  assert schedule.configure(peers, short, DownloadScheduleTick(10)) ==
      DownloadScheduleError.InvalidPolicy
  short = policy(8, 0)
  assert schedule.configure(peers, short, DownloadScheduleTick(10)) ==
      DownloadScheduleError.InvalidPolicy
  assert schedule.configure(peers, policy(), DownloadScheduleTick(9)) ==
      DownloadScheduleError.ClockRegression
  let attempt = schedule.take(10, 1)
  assert schedule.configure(peers, policy(), DownloadScheduleTick(10)) == DownloadScheduleError.Busy
  assert schedule.finish(attempt, DownloadAttemptOutcome.Retry, DownloadScheduleTick(9)) ==
      DownloadScheduleError.ClockRegression
  assert schedule.busy
  assert schedule.finish(attempt, DownloadAttemptOutcome.Retry, DownloadScheduleTick(10)) ==
      DownloadScheduleError.None
  let next = schedule.take(10, 2)
  assert schedule.finish(next, DownloadAttemptOutcome.Adopted, DownloadScheduleTick(10)) ==
      DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(10)).error == DownloadScheduleError.Completed

proc rotation() =
  ## Per-peer cooldown, exact boundaries and rotation retain fair deterministic order.
  var schedule = default(DownloadSchedule)
  let peers = [DownloadPeerId(1), DownloadPeerId(2), DownloadPeerId(3)]
  assert schedule.configure(peers, policy(), DownloadScheduleTick(0)) == DownloadScheduleError.None
  for peer in 1'u64..3'u64:
    let attempt = schedule.take(peer - 1, peer)
    assert schedule.finish(attempt, DownloadAttemptOutcome.Empty, DownloadScheduleTick(peer)) ==
        DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(2)).error == DownloadScheduleError.ClockRegression
  assert schedule.select(DownloadScheduleTick(10)).error == DownloadScheduleError.Waiting
  let first = schedule.take(11, 1)
  assert schedule.finish(first, DownloadAttemptOutcome.Retry, DownloadScheduleTick(11)) ==
      DownloadScheduleError.None
  let second = schedule.take(12, 2)
  assert schedule.finish(second, DownloadAttemptOutcome.Retry, DownloadScheduleTick(12)) ==
      DownloadScheduleError.None
  let third = schedule.take(13, 3)
  assert schedule.finish(third, DownloadAttemptOutcome.Retry, DownloadScheduleTick(13)) ==
      DownloadScheduleError.None
  let again = schedule.take(22, 1)
  assert schedule.finish(again, DownloadAttemptOutcome.Retry, DownloadScheduleTick(30)) ==
      DownloadScheduleError.None
  let last = schedule.take(30, 2)
  assert schedule.finish(last, DownloadAttemptOutcome.Retry, DownloadScheduleTick(30)) ==
      DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(100)).error == DownloadScheduleError.Exhausted

proc identity() =
  ## Equal local IDs never replace exact immutable attempt identity, even after a fresh plan.
  var schedule = default(DownloadSchedule)
  var foreign = default(DownloadSchedule)
  let peers = [DownloadPeerId(1)]
  assert schedule.configure(peers, policy(), DownloadScheduleTick(0)) == DownloadScheduleError.None
  assert foreign.configure(peers, policy(), DownloadScheduleTick(0)) == DownloadScheduleError.None
  let old = schedule.take(0, 1)
  let other = foreign.take(0, 1)
  assert schedule.finish(other, DownloadAttemptOutcome.Adopted, DownloadScheduleTick(0)) ==
      DownloadScheduleError.StaleAttempt
  assert schedule.finish(default(DownloadAttempt), DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(0)) == DownloadScheduleError.StaleAttempt
  assert schedule.finish(old, DownloadAttemptOutcome.Retry, DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  assert schedule.finish(old, DownloadAttemptOutcome.Retry, DownloadScheduleTick(0)) ==
      DownloadScheduleError.StaleAttempt
  assert schedule.configure(peers, policy(1), DownloadScheduleTick(0)) == DownloadScheduleError.None
  let current = schedule.take(0, 1)
  assert schedule.finish(old, DownloadAttemptOutcome.Adopted, DownloadScheduleTick(0)) ==
      DownloadScheduleError.StaleAttempt
  assert schedule.finish(current, DownloadAttemptOutcome.Retry, DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(100)).error == DownloadScheduleError.Exhausted
  assert foreign.finish(other, DownloadAttemptOutcome.Retry, DownloadScheduleTick(0)) ==
      DownloadScheduleError.None

proc extremes() =
  ## Near-maximum ticks never wrap a deadline or allow premature retry.
  var schedule = default(DownloadSchedule)
  let peers = [DownloadPeerId(7)]
  assert schedule.configure(peers, policy(high(uint64), 10),
    DownloadScheduleTick(high(uint64) - 10)) == DownloadScheduleError.None
  let attempt = schedule.take(high(uint64) - 10, 7)
  assert schedule.finish(attempt, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(high(uint64) - 10)) == DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(high(uint64) - 1)).error ==
      DownloadScheduleError.Waiting
  let final = schedule.take(high(uint64), 7)
  assert schedule.finish(final, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(high(uint64))) == DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(high(uint64))).error == DownloadScheduleError.Waiting

proc capacity() =
  ## The hard peer ceiling accepts exactly 64 copied identities and scans a fully cooling plan.
  var schedule = default(DownloadSchedule)
  var peers = newSeq[DownloadPeerId](64)
  for index in 0..<peers.len: peers[index] = DownloadPeerId(uint64(index +
      1)) # Every identity is nonzero and unique.
  var limits = policy(65, high(uint64))
  limits.peers = ElementLimit(64)
  assert schedule.configure(peers, limits, DownloadScheduleTick(0)) == DownloadScheduleError.None
  for peer in 1'u64..64'u64:
    let attempt = schedule.take(0, peer)
    assert schedule.finish(attempt, DownloadAttemptOutcome.Retry,
      DownloadScheduleTick(0)) == DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(0)).error == DownloadScheduleError.Waiting
  let next = schedule.take(high(uint64), 1)
  assert schedule.finish(next, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(high(uint64))) == DownloadScheduleError.None
  assert schedule.select(DownloadScheduleTick(high(uint64))).error ==
      DownloadScheduleError.Exhausted

proc cycle() =
  ## Scoped lease aliases and their schedule release without retaining a peer list or certificate graph.
  var schedule = default(DownloadSchedule)
  assert schedule.configure([DownloadPeerId(1)], policy(1), DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  let attempt = schedule.take(0, 1)
  let alias = attempt
  assert schedule.finish(alias, DownloadAttemptOutcome.Adopted, DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  assert uint64(attempt.peer) == 1 # Detached immutable leases remain readable after acknowledgement.

configuration()
rotation()
identity()
extremes()
capacity()
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # Every scoped owner retires before the next occupancy observation.
let after = getOccupiedMem()
assert before == after
recordArcRelease("application_download_schedule_arc_release", 1000, before, after)
echo "Application download schedule passed"
echo "ARC_RELEASE cycles=1000 unchanged"
