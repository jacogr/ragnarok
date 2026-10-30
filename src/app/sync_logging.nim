# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded human-readable sync observations never participate in readiness or canonical decisions.
## The host supplies a fresh copied sample and its monotonic elapsed time after each completed turn.

import ../lib/logging
import "../jamnp-s/current/sync" as current_sync
import "../jamnp-s/announcements"
import ./node_logging

type SyncLogState* = object ## Fixed scalar history limits output without retaining canonical or peer owners.
  emitted, reportedReady: bool
  lastAt, lastImported: uint64
  lastStage: CurrentSyncStage

func level(stage: CurrentSyncStage): LogLevel =
  ## Unknown evidence is normal; unresolved targets warn and actual host failure is an error.
  case stage
  of CurrentSyncStage.Blocked: LogLevel.Warn
  of CurrentSyncStage.Failed: LogLevel.Error
  else: LogLevel.Info

func label(stage: CurrentSyncStage): string =
  ## Idle is explicitly scoped to the observed targets, never network-wide finality or author election.
  case stage
  of CurrentSyncStage.CatchingUp: "Syncing"
  of CurrentSyncStage.CaughtUp: "Idle (caught up to observed peer targets)"
  of CurrentSyncStage.Blocked: "Sync blocked (unresolved peer target)"
  of CurrentSyncStage.Failed: "Sync failed"
  of CurrentSyncStage.Closed: "Sync stopped"
  of CurrentSyncStage.Uninitialized, CurrentSyncStage.Unknown: "Waiting for sync target"

proc report(state: var SyncLogState, writer: LogWriter, stage: CurrentSyncStage,
    local: AnnouncedBlock, known: bool, target: AnnouncedBlock, sources: int,
    imported: uint64, counted, authoring: bool, now: uint64) =
  ## Stage changes are limited to one per second; unchanged status repeats every five seconds.
  ## The first caught-up milestone and failures bypass that delay; filters precede formatting.
  let severity = level(stage)
  if not writer.enabled(LogTarget.Startup, severity): return
  if state.emitted:
    if now < state.lastAt: return # A regressed diagnostic clock cannot wrap the cadence/rate arithmetic.
    let elapsed = now - state.lastAt
    let changed = stage != state.lastStage
    let firstReady = stage == CurrentSyncStage.CaughtUp and not state.reportedReady
    if elapsed < uint64(NodeStatusIntervalMs) and
        (not changed or (elapsed < 1000 and stage != CurrentSyncStage.Failed and
            not firstReady)): return
  var message = label(stage) & ", best: slot #" & $uint32(local.slot) & " (" &
    shortHash(array[32, byte](local.hash)) & "), peer target: "
  if known:
    let localSlot = uint32(local.slot)
    let targetSlot = uint32(target.slot)
    # Sparse slots count elapsed positions, not blocks; same-slot conflicting hashes can still block.
    let lag = if targetSlot > localSlot: targetSlot - localSlot else: 0'u32
    message.add("slot #" & $targetSlot & " (" & shortHash(array[32, byte](target.hash)) &
      "), lag: " & $lag & " slots")
  else:
    message.add("unknown, lag: unknown")
  message.add(", live sources: " & $sources)
  if counted:
    message.add(", imported: " & $imported)
    if state.emitted and now > state.lastAt and imported >= state.lastImported:
      # Saturate before multiplication; a stalled/very long lifetime must not wrap its diagnostic rate.
      let delta = min(imported - state.lastImported, high(uint64) div 10000)
      let tenths = delta * 10000 div (now - state.lastAt)
      message.add(" (" & $(tenths div 10) & "." & $(tenths mod 10) & " blocks/s)")
  message.add(", full state ready: " & $(stage == CurrentSyncStage.CaughtUp) &
    ", light ready: false")
  if authoring:
    message.add(", authoring gate: " & (if stage ==
        CurrentSyncStage.CaughtUp: "open" else: "closed"))
  log(writer, LogTarget.Startup, severity, message)
  state.emitted = true
  state.lastAt = now
  state.lastImported = imported
  state.lastStage = stage
  if stage == CurrentSyncStage.CaughtUp: state.reportedReady = true

proc logSyncProgress*(state: var SyncLogState, writer: LogWriter,
    progress: CurrentSyncProgress, now: uint64) =
  ## Continuous imports report only host-confirmed counters and copied local/target identities.
  let known = progress.hasTarget
  let target = if known: progress.target else: default(AnnouncedBlock)
  state.report(writer, progress.stage, progress.localHead, known, target, progress.liveSources,
    progress.adoptedBlocks, true, false, now)

proc logSyncProgress*(state: var SyncLogState, writer: LogWriter,
    progress: SyncTargetProgress, local: AnnouncedBlock, now: uint64) =
  ## Tiny reports its freshly sampled gate; an open gate does not claim this validator won a slot.
  let known = progress.hasTarget
  let target = if known: progress.target else: default(AnnouncedBlock)
  state.report(writer, progress.stage, local, known, target, progress.liveSources, 0, false, true, now)
