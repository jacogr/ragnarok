# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared full-state target evidence for continuous import and Tiny participation. Only real live
## stream snapshots refresh source age; only independently anchored canonical views satisfy targets.

import ./[announcements, announcement_stream]
import ../app/download_schedule
import ../codec/header
import ../chain/[provider, genesis]

type
  CurrentSyncStage* {.pure.} = enum ## Unknown, blocked, failed and closed observations never grant readiness.
    Uninitialized, Unknown, CatchingUp, CaughtUp, Blocked, Failed, Closed
  SyncTargetProgress* = object ## Immutable copied scalars describe evidence as of one completed host turn.
    status: CurrentSyncStage
    selected: AnnouncedBlock
    known: bool
    sources: int
  TargetSource = object ## Receipt retention is bounded by this stream's current advertised leaf cap.
    incarnation, sequence, seenAt: uint64
    live, sampled: bool
    leaves, reached: seq[AnnouncedBlock]
  SyncTargets* = object ## One explicit host owns monotonic source observations and its independent initial anchor.
    configured, turnActive: bool
    peers: seq[DownloadPeerId]
    sources: array[16, TargetSource]
    ageMs, now: uint64
    anchor, initial, local: AnnouncedBlock
    progress: SyncTargetProgress

func stage*(progress: SyncTargetProgress): CurrentSyncStage =
  ## Failed/default evidence never becomes an implicit caught-up state.
  progress.status
func fullReady*(progress: SyncTargetProgress): bool =
  ## Only a whole turn evaluated against actual canonical full-state ancestry can succeed.
  progress.status == CurrentSyncStage.CaughtUp
func lightReady*(progress: SyncTargetProgress): bool =
  ## Full-state ancestry supplies no independent light-client trust authority.
  false
func hasTarget*(progress: SyncTargetProgress): bool =
  ## A missing live source has no extractable target record.
  progress.known
func target*(progress: SyncTargetProgress): AnnouncedBlock {.requires: progress.known.} =
  ## Maximal advertised slot is a download hint, never a finality or fork-choice decision.
  progress.selected
func liveSources*(progress: SyncTargetProgress): int =
  ## Count only freshly sampled authenticated sources, independently of their validity as targets.
  progress.sources
func stamp(head: BlockSnapshot): AnnouncedBlock =
  ## Retain copied hash/slot metadata without holding a canonical ARC graph between worker turns.
  AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](head.blockHash)),
    slot: HeaderSlot(head.slot))
proc configure*(targets: var SyncTargets, view: ChainView, peers: seq[DownloadPeerId],
    ageMs, now: uint64): bool =
  ## Select an actual independent complete-state startup view before accepting any peer observations.
  if targets.configured or view.fuzzOnly: return false
  if peers.len == 0 or peers.len > 16 or ageMs == 0: return false
  let head = view.bestBlock
  if head.error != GenesisError.None: return false
  for index, peer in peers:
    if uint64(peer) == 0: return false
    for previous in 0..<index:
      if peers[previous] == peer: return false # Aliases cannot acquire extra freshness or corroboration weight.
  targets.peers = @[]
  for peer in peers: targets.peers.add(peer)
  targets.initial = stamp(head.value)
  targets.local = targets.initial
  let finalized = view.finalizedBlock
  targets.anchor = if finalized.error == GenesisError.None: stamp(
      finalized.value) else: targets.initial
  targets.ageMs = ageMs
  targets.now = now
  targets.configured = true
  targets.progress.status = CurrentSyncStage.Unknown
  true
proc beginTurn*(targets: var SyncTargets, now: uint64): bool =
  ## Every configured source must be sampled again; unchanged snapshots never extend their timestamp.
  if not targets.configured or now < targets.now:
    targets.progress = SyncTargetProgress(status: CurrentSyncStage.Failed)
    targets.turnActive = false
    return false
  targets.turnActive = true
  targets.now = now
  targets.progress = SyncTargetProgress(status: CurrentSyncStage.Unknown)
  for index in 0..<targets.peers.len: targets.sources[index].sampled = false
  true
proc observePeer*(targets: var SyncTargets, peer: DownloadPeerId,
    incarnation: uint64, snapshot: PeerAnnouncementSnapshot): bool =
  ## Only an available real stream snapshot can supply leaves, sequence and new-source provenance.
  if not targets.configured or not targets.turnActive: return false
  var found = -1
  for index, configured in targets.peers:
    if peer == configured: found = index
  if found < 0 or targets.sources[found].sampled: return false
  let source = addr targets.sources[found]
  if not snapshot.available:
    source[] = TargetSource(sampled: true)
    return true # TLS failure, reset, FIN or retirement revokes both freshness and old receipts immediately.
  let claims = snapshot.value
  let leaves = if claims.leaves.len == 0: @[claims.finalized] else: claims.leaves
  if not source.live or source.incarnation != incarnation or source.sequence != claims.sequence:
    var reached: seq[AnnouncedBlock] = @[]
    if source.live and source.incarnation == incarnation:
      for leaf in leaves:
        for installed in source.reached:
          if leaf == installed: reached.add(leaf) # Only still-advertised exact receipts survive a message update.
    var captured: seq[AnnouncedBlock] = @[]
    for leaf in leaves: captured.add(leaf) # Private source storage never aliases a caller's copied snapshot payload.
    source[] = TargetSource(live: true, incarnation: incarnation, sequence: claims.sequence,
      seenAt: targets.now, leaves: captured, reached: reached)
  source.sampled = true
  if targets.now - source.seenAt >= targets.ageMs: return true
  inc targets.progress.sources
  for leaf in source.leaves:
    if not targets.progress.known or uint32(leaf.slot) > uint32(targets.progress.selected.slot):
      targets.progress.selected = leaf
      targets.progress.known = true # A Final-only handshake is still an untrusted exact download hint.
  true
proc fresh*(targets: SyncTargets, peer: DownloadPeerId): bool =
  ## Idle reconnect policy consumes only monotonic source metadata, never canonical graph aliases.
  for index, configured in targets.peers:
    if configured == peer:
      let source = targets.sources[index]
      return source.sampled and source.live and targets.now - source.seenAt < targets.ageMs
  false
proc pending*(targets: var SyncTargets): SyncTargetProgress =
  ## Worker/input/publication ownership prevents readiness while preserving copied target diagnostics.
  targets.turnActive = false
  targets.progress.status = if targets.progress.sources == 0: CurrentSyncStage.Unknown
    else: CurrentSyncStage.CatchingUp
  targets.progress
func progress*(targets: SyncTargets): SyncTargetProgress =
  ## Read only the last whole-turn observation; callers start a new turn before later participation.
  targets.progress
proc recordInstalled*(targets: var SyncTargets, view: ChainView): bool =
  ## Advance only from an actual full canonical view; sparse slots still represent one validated child.
  targets.turnActive = false
  targets.progress.status = CurrentSyncStage.Unknown
  if not targets.configured or view.fuzzOnly: return false
  let selected = view.bestBlock
  if selected.error != GenesisError.None: return false
  let head = stamp(selected.value)
  if head != targets.local:
    let parent = AnnouncedHeaderHash(array[32, byte](selected.value.parentHash))
    if parent != targets.local.hash or uint32(head.slot) <= uint32(targets.local.slot):
      targets.progress.status = CurrentSyncStage.Blocked
      return false # A producer cannot skip/reparent the independently anchored selected history.
    targets.local = head
  targets.progress.status = CurrentSyncStage.Unknown
  true
proc evaluate*(targets: var SyncTargets, view: ChainView): SyncTargetProgress =
  ## Call only outside native canonical leases; the actual full view proves each old/current target.
  let active = targets.turnActive
  targets.turnActive = false
  let selected = view.bestBlock
  let usable = targets.configured and not view.fuzzOnly
  if not active or not usable or selected.error != GenesisError.None:
    targets.progress.status = CurrentSyncStage.Failed
    return targets.progress
  let head = stamp(selected.value)
  if head != targets.local:
    let parent = AnnouncedHeaderHash(array[32, byte](selected.value.parentHash))
    if parent != targets.local.hash or uint32(head.slot) <= uint32(targets.local.slot):
      targets.progress.status = CurrentSyncStage.Blocked
      return targets.progress # A caller cannot replace the anchored history with an unrelated or skipped view.
    targets.local = head
  var ahead = false
  var conflict = false
  for index in 0..<targets.peers.len:
    let source = addr targets.sources[index]
    if not source.sampled:
      targets.progress.status = CurrentSyncStage.Unknown
      return targets.progress # A skipped source sample cannot preserve yesterday's permission to author.
    if not source.live or targets.now - source.seenAt >= targets.ageMs: continue
    for leaf in source.leaves:
      if uint32(leaf.slot) > uint32(head.slot):
        ahead = true
      else:
        var matched = leaf == targets.anchor or leaf == targets.initial or leaf == head
        for installed in source.reached:
          if installed == leaf: matched = true
        if not matched:
          let retained = view.blockAt(BlockHash(array[32, byte](leaf.hash)))
          if retained.error == GenesisError.None and retained.value.slot == uint32(leaf.slot):
            matched = true # Canonical retention proves ancestry; a peer's slot number alone does not.
        if matched:
          var recorded = false
          for installed in source.reached:
            if installed == leaf: recorded = true
          if not recorded: source.reached.add(leaf) # At most one receipt per distinct current target is retained.
        else:
          conflict = true # Unknown older forks and same-slot/different-hash claims fail closed.
  if targets.progress.sources == 0: targets.progress.status = CurrentSyncStage.Unknown
  elif conflict: targets.progress.status = CurrentSyncStage.Blocked
  elif ahead: targets.progress.status = CurrentSyncStage.CatchingUp
  else: targets.progress.status = CurrentSyncStage.CaughtUp
  targets.progress
