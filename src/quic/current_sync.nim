# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Continuous full-state catch-up over persistent authenticated discovery and ordinary current
## admission. Targets are hints; only installed canonical children advance the local observation.

import ./[current_block_download_loop, current_block_download_peers, announcement_stream,
    announcements, current_block_download_session]
import ../app/[services, download_schedule, current_handoff, current_logical_download, chain]
import ../codec/[bounded, header]
import ../chain/[provider, genesis]
import ../state/[store, report_anchors]

type
  CurrentSyncStage* {.pure.} = enum ## Unknown and blocked observations never authorize participation.
    Uninitialized, Unknown, CatchingUp, CaughtUp, Blocked, Failed, Closed
  CurrentSyncError* {.pure.} = enum ## Refusals never grant canonical installation or readiness.
    None, Uninitialized, Busy, InvalidPolicy, MissingState, ClockRegression, DispatchFailure,
      InvalidAdoption, NeedsAncestors
  CurrentSyncLimits* = object ## Source freshness, connection retries and import budgets are independent.
    download*: CurrentDownloadLoopLimits
    announcements*: AnnouncementLimits
    sourceAgeMs*, reconnectMs*: uint64
  CurrentSyncProgress* = object ## Detached scalar status carries no state root or execution authority.
    status: CurrentSyncStage
    local: AnnouncedBlock
    target: AnnouncedBlock
    targetKnown: bool
    adopted: uint64
    sources: int
  SyncEndpoint = object ## Fixed identities retain credentials through explicit endpoint replacement.
    present: bool
    key: CurrentDownloadPeerKey
    port: uint16
    certificate, privateKey, alpn: string
    dialedAt: uint64
  SyncSource = object ## Only an actual stream message refreshes the monotonic evidence timestamp.
    incarnation, sequence, seenAt: uint64
    live: bool
    leaves, reached: seq[AnnouncedBlock]
  CurrentSync* = object ## Stable exclusive owner; close must precede Services or callback retirement.
    dispatcher: CurrentDownloadLoop
    owner: nil ptr Services
    peers: seq[DownloadPeerId]
    endpoints: array[16, SyncEndpoint]
    sources: array[16, SyncSource]
    limits: CurrentSyncLimits
    progress: CurrentSyncProgress
    previous: OwnedHeader
    older: seq[OwnedHeader]
    known: seq[AnnouncedBlock]
    finalized: AnnouncedBlock
    lastTick, exhaustedAt: uint64
    retrying: bool

proc `=copy`*(destination: var CurrentSync, source: CurrentSync) {.error:
    "CurrentSync owns stable callbacks and an exclusive Services borrow".}
  ## Copying would duplicate callback addresses and canonical receipt consumption.
proc `=dup`*(source: CurrentSync): CurrentSync {.error.}
  ## Composite ownership is explicit even when a nested dispatcher is already non-copyable.

func stage*(progress: CurrentSyncProgress): CurrentSyncStage =
  ## Defaults and closed hosts carry no readiness.
  progress.status
func localHead*(progress: CurrentSyncProgress): AnnouncedBlock =
  ## This scalar is descriptive; only the host's validated startup/adoption can change it.
  progress.local
func hasTarget*(progress: CurrentSyncProgress): bool =
  ## Missing live evidence has no extractable target.
  progress.targetKnown
func target*(progress: CurrentSyncProgress): AnnouncedBlock {.requires: progress.targetKnown.} =
  ## A peer target remains untrusted even when its hash is reached locally.
  progress.target
func adoptedBlocks*(progress: CurrentSyncProgress): uint64 =
  ## Count installed children, independently of their possibly sparse slot numbers.
  progress.adopted
func liveSources*(progress: CurrentSyncProgress): int =
  ## Count fresh authenticated sources with nonempty target evidence.
  progress.sources
func fullReady*(progress: CurrentSyncProgress): bool =
  ## This copied observation is only current as of its producing host tick.
  progress.status == CurrentSyncStage.CaughtUp
func lightReady*(progress: CurrentSyncProgress): bool =
  ## Full execution provides no independent light trust certificate.
  false
func progress*(sync: CurrentSync): CurrentSyncProgress =
  ## Copy fixed metadata only; canonical graphs and callbacks stay with their owners.
  sync.progress

proc configure(sync: var CurrentSync, owner: var Services, peers: seq[DownloadPeerId],
    older: seq[OwnedHeader], limits: CurrentSyncLimits, now: CurrentDownloadLoopTick,
    logical: CurrentLogicalDownloadPolicy, qualified: bool): CurrentSyncError =
  ## Capture a real complete-state anchor before borrowing Services or opening a TLS endpoint.
  if sync.progress.status != CurrentSyncStage.Uninitialized: return CurrentSyncError.Busy
  if limits.sourceAgeMs == 0 or limits.reconnectMs == 0 or peers.len == 0 or peers.len > 16 or
      uint64(limits.download.schedule.retryDelay) == 0 or not limits.announcements.valid:
    return CurrentSyncError.InvalidPolicy
  if owner.preparationActive or owner.stateProofActive or owner.diskPublicationActive:
    return CurrentSyncError.Busy # No canonical alias escapes a current worker lease.
  if owner.stateSnapshot.error != StateStoreError.None: return CurrentSyncError.MissingState
  let head = owner.chainView.bestBlock
  let selectedFinality = owner.chainView.finalizedBlock
  if head.error != GenesisError.None:
    return CurrentSyncError.MissingState # A peer's claimed finality never supplies this local anchor.
  let local = AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](head.value.blockHash)),
    slot: HeaderSlot(head.value.slot))
  let original = owner.startupBlockAnchor
  if not original.available: return CurrentSyncError.MissingState
  # A restored best head can contain unfinalized imports. Only separately selected local finality
  # or the independently configured startup checkpoint can supply the advertised fixed anchor.
  let anchor = if selectedFinality.error == GenesisError.None:
      AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](selectedFinality.value.blockHash)),
        slot: HeaderSlot(selectedFinality.value.slot))
    else: AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](original.blockHash)),
      slot: original.slot)
  let configured = if qualified:
      sync.dispatcher.configure(owner, peers, older, limits.download, now, logical)
    else: sync.dispatcher.configure(owner, peers, older, limits.download, now)
  if configured != CurrentDownloadLoopError.None: return CurrentSyncError.InvalidPolicy
  sync.owner = addr owner
  if sync.dispatcher.enableAnnouncements(AnnouncementHandshake(finalized: anchor, leaves: @[local]),
      limits.announcements) != CurrentDownloadPeerError.None:
    sync.dispatcher.close()
    sync.owner = nil
    return CurrentSyncError.InvalidPolicy # No endpoint exists after refused discovery policy.
  sync.peers = @[]
  for peer in peers: sync.peers.add(peer) # Caller list mutation cannot change fixed scheduling/source identities.
  sync.older = @[]
  for ancestor in older: sync.older.add(ancestor) # Retain only immutable owned headers under the validated count/byte limits.
  sync.previous = head.value.header
  sync.known = @[local]
  sync.finalized = anchor
  sync.limits = limits
  sync.lastTick = uint64(now)
  sync.progress = CurrentSyncProgress(status: CurrentSyncStage.Unknown, local: local)
  CurrentSyncError.None

proc configure*(sync: var CurrentSync, owner: var Services, peers: seq[DownloadPeerId],
    older: seq[OwnedHeader], limits: CurrentSyncLimits,
    now: CurrentDownloadLoopTick): CurrentSyncError =
  ## Raw current operation preserves the existing full-state admission gates.
  sync.configure(owner, peers, older, limits, now, default(CurrentLogicalDownloadPolicy), false)
proc configure*(sync: var CurrentSync, owner: var Services, peers: seq[DownloadPeerId],
    older: seq[OwnedHeader], limits: CurrentSyncLimits, now: CurrentDownloadLoopTick,
    logical: CurrentLogicalDownloadPolicy): CurrentSyncError =
  ## Qualified hosts retain ordinary complete logical continuation across every adopted child.
  sync.configure(owner, peers, older, limits, now, logical, true)

proc openPeer*(sync: var CurrentSync, id: DownloadPeerId, expected: CurrentDownloadPeerKey,
    port: uint16, certificate, key, alpn: string): CurrentDownloadPeerError =
  ## Capture one prevalidated fixed pin only after the ordinary catalog accepted its endpoint.
  var found = -1
  for index, peer in sync.peers:
    if peer == id: found = index # The configured dispatcher already rejected duplicate IDs.
  if found < 0: return CurrentDownloadPeerError.InvalidPeer
  let opened = sync.dispatcher.openPeer(id, expected, port, certificate, key, alpn)
  if opened != CurrentDownloadPeerError.None: return opened
  sync.endpoints[found] = SyncEndpoint(present: true, key: expected, port: port,
    certificate: certificate, privateKey: key, alpn: alpn, dialedAt: sync.lastTick)
  CurrentDownloadPeerError.None

proc observe(sync: var CurrentSync, now: uint64) =
  ## Recompute readiness from all live leaves; lower competing forks cannot be silently ignored.
  sync.progress.targetKnown = false
  sync.progress.sources = 0
  var conflict = false
  var ahead = false
  for index, peer in sync.peers:
    let view = sync.dispatcher.announcements(peer)
    let incarnation = sync.dispatcher.incarnation(peer)
    if not view.available:
      sync.sources[index] = default(SyncSource)
      continue # TLS/reset/FIN revoke evidence immediately, without waiting for TTL.
    let claims = view.value
    let targets = if claims.leaves.len == 0: @[claims.finalized] else: claims.leaves
    # A peer with no unfinalized leaves still names a download target. Its Final record is a hint,
    # never a substitute for independently anchored ordinary full-state admission.
    let source = addr sync.sources[index]
    if not source.live or source.incarnation != incarnation or source.sequence != claims.sequence:
      var reached: seq[AnnouncedBlock] = @[]
      if source.live and source.incarnation == incarnation:
        for leaf in targets:
          for installed in source.reached:
            if leaf == installed: reached.add(leaf) # Retain only still-advertised exact receipts, bounded by the leaf cap.
      source[] = SyncSource(live: true, incarnation: incarnation, sequence: claims.sequence,
        seenAt: now, leaves: targets, reached: reached) # Repeated polling never extends freshness.
    if now - source.seenAt >= sync.limits.sourceAgeMs: continue
    inc sync.progress.sources
    for leaf in source.leaves:
      if not sync.progress.targetKnown or uint32(leaf.slot) > uint32(sync.progress.target.slot):
        sync.progress.target = leaf
        sync.progress.targetKnown = true # Max slot is a download hint, never a fork-choice rule.
      if uint32(leaf.slot) > uint32(sync.progress.local.slot):
        ahead = true
      else:
        var matched = leaf == sync.finalized
        for installed in source.reached:
          if installed == leaf: matched = true # A previously reached exact claim survives rolling header eviction.
        if not matched:
          for canonical in sync.known:
            if canonical == leaf: matched = true # Only locally observed installed ancestry satisfies an old target.
          let borrowed = sync.owner
          if not matched and borrowed != nil:
            let owner: ptr Services = borrowed
            if not owner[].preparationActive and not owner[].stateProofActive and not owner[].diskPublicationActive:
              let retained = owner[].chainView.blockAt(BlockHash(array[32, byte](leaf.hash)))
              if retained.error == GenesisError.None and retained.value.slot == uint32(leaf.slot):
                matched = true # Existing canonical retention can prove an old target after a new source handshake.
          if matched: source.reached.add(leaf) # At most one proof per distinct current source leaf is retained.
        if not matched: conflict = true # Unknown old forks require explicit reconciliation; no rollback is invented.
  if sync.progress.sources == 0:
    sync.progress.status = CurrentSyncStage.Unknown
  elif conflict:
    sync.progress.status = CurrentSyncStage.Blocked
  elif ahead:
    sync.progress.status = CurrentSyncStage.CatchingUp
  else:
    sync.progress.status = CurrentSyncStage.CaughtUp # Every fresh nonempty leaf is actual locally installed ancestry.

proc retainParent(sync: var CurrentSync, child: OwnedHeader): bool =
  ## Retain a contiguous newest-first bounded window; total imports never reserve growing storage.
  let policy = sync.limits.download
  let report = policy.candidate.reporting.reports.ancestors
  let info = child.headerInfo
  if info.error != HeaderError.None or uint64(info.value.consumed) > uint64(report.maxBytes):
    return false
  var reportBytes = uint64(report.maxBytes) - uint64(info.value.consumed)
  var inputBytes = uint64(policy.input.ancestorBytes)
  var next: seq[OwnedHeader] = @[]
  for index in 0..sync.older.len:
    if uint64(next.len) >= uint64(policy.input.ancestors) or
        uint64(next.len) + 1 >= uint64(report.headers): break # The child consumes one separate report header.
    let parent = if index == 0: sync.previous else: sync.older[index - 1]
    let size = parent.headerInfo
    if size.error != HeaderError.None: return false
    let bytes = uint64(size.value.consumed)
    if bytes > reportBytes or bytes > inputBytes: break # Evict only the oldest suffix, preserving contiguity.
    reportBytes -= bytes
    inputBytes -= bytes
    next.add(parent)
  sync.older = next
  sync.previous = child
  true

proc tick*(sync: var CurrentSync, now: CurrentDownloadLoopTick): CurrentSyncError =
  ## One bounded host turn polls discovery, advances one import phase and observes actual adoption.
  if sync.progress.status == CurrentSyncStage.Uninitialized: return CurrentSyncError.Uninitialized
  if sync.progress.status in [CurrentSyncStage.Failed,
      CurrentSyncStage.Closed]: return CurrentSyncError.Busy
  if uint64(now) < sync.lastTick:
    sync.progress.status = CurrentSyncStage.Failed
    return CurrentSyncError.ClockRegression
  sync.lastTick = uint64(now)
  sync.observe(uint64(now)) # Expiration or source retirement revokes eligibility before a new input can start.
  let acquire = sync.progress.status == CurrentSyncStage.CatchingUp
  if sync.dispatcher.tick(now, acquire) != CurrentDownloadLoopError.None:
    sync.progress.status = CurrentSyncStage.Failed
    return CurrentSyncError.DispatchFailure
  if sync.dispatcher.stage == CurrentDownloadLoopStage.Adopted:
    let receipt = sync.dispatcher.adoption
    let borrowed = sync.owner
    if borrowed == nil: return CurrentSyncError.Uninitialized
    let owner: ptr Services = borrowed
    let canonical = owner[].chainView.bestBlock
    if receipt.error != CurrentHandoffError.None or canonical.error != GenesisError.None:
      sync.progress.status = CurrentSyncStage.Failed
      return CurrentSyncError.InvalidAdoption
    let child = receipt.value
    let parentHash = AnnouncedHeaderHash(array[32, byte](child.parentHash))
    let childHash = array[32, byte](child.blockHash)
    let canonicalHash = array[32, byte](canonical.value.blockHash)
    let childSlot = uint32(child.slot)
    let localSlot = uint32(sync.progress.local.slot)
    if parentHash != sync.progress.local.hash or childSlot <= localSlot or
        childHash != canonicalHash or sync.progress.adopted == high(uint64):
      sync.progress.status = CurrentSyncStage.Failed
      return CurrentSyncError.InvalidAdoption # Producer status alone cannot acknowledge a changed/unrelated canonical head.
    if not sync.retainParent(child.header):
      sync.progress.status = CurrentSyncStage.Failed
      return CurrentSyncError.InvalidPolicy
    inc sync.progress.adopted
    sync.progress.local = AnnouncedBlock(hash: AnnouncedHeaderHash(array[32, byte](
        child.blockHash)),
      slot: HeaderSlot(child.slot))
    sync.known.add(sync.progress.local)
    if sync.known.len > sync.older.len + 1:
      var retained: seq[AnnouncedBlock] = @[]
      for index in sync.known.len - sync.older.len - 1..<sync.known.len:
        retained.add(sync.known[index]) # Keep only the same bounded observed canonical suffix.
      sync.known = retained
    let published = sync.dispatcher.publishAnnouncement(child.header, sync.finalized)
    if published != AnnouncementError.None:
      sync.progress.status = CurrentSyncStage.Failed
      return CurrentSyncError.DispatchFailure
    if sync.dispatcher.nextChild(sync.older, now) != CurrentDownloadLoopError.None:
      sync.progress.status = CurrentSyncStage.Failed
      return CurrentSyncError.DispatchFailure # Only retired successful adoption can rearm an idle receiver.
  elif sync.dispatcher.stage == CurrentDownloadLoopStage.Exhausted:
    if not sync.retrying:
      sync.retrying = true
      sync.exhaustedAt = uint64(now) # Exhaustion never becomes completion; a later turn renews the bounded plan.
    elif uint64(now) - sync.exhaustedAt >= uint64(sync.limits.download.schedule.retryDelay):
      if sync.dispatcher.restart(now) != CurrentDownloadLoopError.None:
        sync.progress.status = CurrentSyncStage.Failed
        return CurrentSyncError.DispatchFailure
      sync.retrying = false
  elif sync.dispatcher.stage == CurrentDownloadLoopStage.Failed:
    sync.progress.status = CurrentSyncStage.Failed
    return CurrentSyncError.DispatchFailure
  if sync.dispatcher.stage == CurrentDownloadLoopStage.AwaitingAncestors:
    sync.progress.status = CurrentSyncStage.CatchingUp
    return CurrentSyncError.NeedsAncestors # The same input/deadline remains reserved while host-side acquisition runs.
  sync.observe(uint64(now))
  if sync.dispatcher.stage == CurrentDownloadLoopStage.Waiting:
    for index, peer in sync.peers:
      let endpoint = addr sync.endpoints[index]
      let source = sync.sources[index]
      let stale = not source.live or uint64(now) - source.seenAt >= sync.limits.sourceAgeMs
      if endpoint.present and stale and uint64(now) - endpoint.dialedAt >= sync.limits.reconnectMs:
        endpoint.dialedAt = uint64(now)
        let reopened = sync.dispatcher.reconnectPeer(peer, endpoint.key, endpoint.port,
          endpoint.certificate, endpoint.privateKey, endpoint.alpn)
        if reopened != CurrentDownloadPeerError.None:
          discard # An unavailable endpoint remains unknown and is retried only after another bounded delay.
    sync.observe(uint64(now)) # Retired streams cannot retain readiness during a replacement handshake.
  if sync.dispatcher.stage != CurrentDownloadLoopStage.Waiting and sync.progress.fullReady:
    sync.progress.status = CurrentSyncStage.CatchingUp # A live import must retire before readiness can be published.
  CurrentSyncError.None

proc close*(sync: var CurrentSync) =
  ## Join workers/publication and native callbacks before releasing ancestry or the Services borrow.
  sync.dispatcher.close()
  if sync.dispatcher.completed:
    let receipt = sync.dispatcher.adoption
    if receipt.error == CurrentHandoffError.None:
      let child = receipt.value
      let parent = AnnouncedHeaderHash(array[32, byte](child.parentHash))
      if parent == sync.progress.local.hash and child.slot > uint32(sync.progress.local.slot):
        if sync.progress.adopted < high(uint64):
          inc sync.progress.adopted # Joined shutdown can acknowledge this host's already installed pending receipt.
          sync.progress.local = AnnouncedBlock(
            hash: AnnouncedHeaderHash(array[32, byte](child.blockHash)), slot: HeaderSlot(child.slot))
  sync.owner = nil
  sync.previous = default(OwnedHeader)
  sync.older = @[]
  sync.known = @[]
  sync.sources = default(array[16, SyncSource])
  sync.progress.sources = 0
  sync.progress.targetKnown = false
  sync.progress.status = CurrentSyncStage.Closed

proc ancestorDemand*(sync: CurrentSync): CurrentDownloadSessionResult[ReportLookupDemand] =
  ## Only the dispatcher's genuinely suspended current input can authorize acquisition.
  sync.dispatcher.ancestorDemand
proc ancestorRemaining*(sync: CurrentSync, now: CurrentDownloadLoopTick): uint64 =
  ## Retain the original attempt deadline across all bounded acquisition rounds.
  sync.dispatcher.ancestorRemaining(now)
proc ancestors*(sync: CurrentSync): seq[OwnedHeader] =
  ## Caller uses this bounded immutable context only while workers and child peers are retired.
  result = @[]
  for ancestor in sync.older: result.add(ancestor)
proc resumeAncestors*(sync: var CurrentSync, older: seq[OwnedHeader],
    now: CurrentDownloadLoopTick): CurrentSyncError =
  ## The dispatcher validates the complete replacement before the suspended input resumes.
  if sync.dispatcher.resumeAncestors(older, now) != CurrentDownloadLoopError.None:
    return CurrentSyncError.DispatchFailure
  sync.older = @[]
  for ancestor in older: sync.older.add(ancestor) # Replacement owns its ordering after caller-side acquisition returns.
  CurrentSyncError.None

func retainedAncestors*(sync: CurrentSync): int =
  ## Report the bounded rolling context count without exposing any canonical header owner.
  sync.older.len
