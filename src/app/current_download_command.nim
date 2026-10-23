# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded successive-child command owns canonical Services and stable download callbacks through explicit teardown.
## Startup accepts only explicit state/stage policies and a bounded pinned loopback peer list; no fixture or process-global inputs.

import std/[syncio, monotimes, times]
import std/posix/posix
import ./[options, services, chain, current_handoff, current_download_policy,
    current_block_download, ancestor_inputs, ancestor_response, current_logical_download,
    current_logical_startup]
import ./download_schedule
import ../codec/[bounded, header]
import ../state/report_anchors
import ../chain/[genesis, provider]
import ../quic/[current_block_download_loop, current_block_download_session,
    current_block_download_peers, ancestor_peer, ancestor_stream]

type CurrentDownloadCommandResult* {.pure.} = enum ## Process-level refusal never implies a prepared or adopted successor.
  Uninitialized, Adopted, InvalidOptions, InvalidEndpoint, InvalidIdentity, InvalidPolicy,
  InvalidAncestors, StartupFailure, AdmissionFailure, TransportFailure, DispatchFailure, Exhausted,
    Timeout, StorageMaintenanceFailure, InvalidLogicalSource

type CurrentDownloadCommandOutcome* = object ## Immutable scalar diagnostics describe confirmed installed progress, never execution authority.
  status: CurrentDownloadCommandResult
  requested, adopted: int

func error*(outcome: CurrentDownloadCommandOutcome): CurrentDownloadCommandResult =
  ## Preserve the terminal reason independently of earlier confirmed progress.
  outcome.status
func requestedBlocks*(outcome: CurrentDownloadCommandOutcome): int =
  ## Report the validated finite request; invalid/default options have zero requested work.
  outcome.requested
func adoptedBlocks*(outcome: CurrentDownloadCommandOutcome): int =
  ## Count actual canonical advancement observed only after joined child teardown, including confirmed shutdown receipts.
  outcome.adopted

proc number(text: string, maximum: uint64): uint64 =
  ## Positive canonical decimal parsing proves arithmetic/conversion bounds before native setup.
  if text.len == 0 or text.len > 20 or text[0] == '0': return 0
  var value = 0'u64
  for character in text:
    if character notin {'0'..'9'}: return 0 # No sign, exponent, whitespace or unknown command mode becomes an endpoint.
    let digit = uint64(ord(character) - ord('0'))
    if value > (maximum - digit) div 10: return 0 # maximum >=9 for both callers, proving subtraction too.
    value = value * 10 + digit
  value

proc identity(path: string, expected: var CurrentDownloadPeerKey): bool {.raises.} =
  ## A public identity file must be exactly 32 bytes, including detection of concurrent file growth.
  expected = default(CurrentDownloadPeerKey)
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return false
  defer: close(file) # No native certificate callback borrows file storage.
  var bytes = default(array[33, byte])
  if readBuffer(file, addr bytes[0], bytes.len) != 32: return false
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = bytes[index] # Copy only the exact proven public key payload.
  expected = CurrentDownloadPeerKey(key)
  true

proc ancestorsFit(head: OwnedHeader, older: seq[OwnedHeader],
    limits: CurrentDownloadLoopLimits): bool =
  ## Bound actual retained bytes/counts for the next request, including the selected parent in report validation.
  let config = limits.candidate.reporting.reports.ancestors
  if uint64(older.len) > uint64(limits.input.ancestors) or uint64(older.len) >= uint64(
      config.headers):
    return false # Parent consumes one additional validator header.
  var inputBytes = uint64(limits.input.ancestorBytes)
  var reportBytes = uint64(config.maxBytes)
  for index in 0..older.len:
    let owner = if index == 0: head else: older[index - 1]
    let info = owner.headerInfo
    if info.error != HeaderError.None: return false # No default or invalid selected/retained header becomes context.
    let size = uint64(info.value.consumed)
    if size > uint64(config.header.maxBytes) or size > reportBytes: return false
    reportBytes -= size # Subtraction proves cumulative parent-plus-ancestor accounting.
    if index > 0:
      if size > inputBytes: return false # Only older headers consume the receiver's separate retained-byte budget.
      inputBytes -= size
  true

type RemoteAncestorResult = object ## A refused acquisition retains no decoded prefix or partially extended input list.
  case successful: bool
  of true:
    captured: seq[OwnedHeader]
  else:
    refusal: CurrentDownloadCommandResult

proc remoteAncestors(owner: var Services, options: Options, peers: seq[DownloadPeerId],
    ports: array[16, uint16], keys: array[16, CurrentDownloadPeerKey], older: seq[OwnedHeader],
    limits: CurrentDownloadLoopLimits, started: MonoTime,
        timeout: uint64, maximum: ElementLimit): RemoteAncestorResult {.raises.} =
  ## Acquire only missing context, before any execution worker lease; native peer cleanup precedes returning copied headers.
  let selected = owner.chainView.bestBlock
  if selected.error != GenesisError.None or not ancestorsFit(selected.value.header, older, limits):
    return RemoteAncestorResult(successful: false,
        refusal: CurrentDownloadCommandResult.InvalidAncestors)
  let head = selected.value.header
  let child = if older.len == 0: head else: older[older.high]
  let request = initAncestorRequest(child, maximum)
  if request.error != AncestorResponseError.None:
    return RemoteAncestorResult(successful: false,
        refusal: CurrentDownloadCommandResult.InvalidAncestors)
  var inputBytes = uint64(limits.input.ancestorBytes)
  var reportBytes = uint64(limits.candidate.reporting.reports.ancestors.maxBytes)
  reportBytes -= uint64(head.headerInfo.value.consumed) # ancestorsFit proved all independent subtraction bounds.
  for header in older:
    let size = uint64(header.headerInfo.value.consumed)
    inputBytes -= size
    reportBytes -= size # Only parent-inclusive report bytes charge the selected head.
  let headerBytes = ByteLimit(min(inputBytes, reportBytes))
  var schedule = default(DownloadSchedule)
  if schedule.configure(peers, limits.schedule, DownloadScheduleTick(0)) !=
      DownloadScheduleError.None:
    return RemoteAncestorResult(successful: false,
        refusal: CurrentDownloadCommandResult.InvalidPolicy)
  var peer = default(AncestorPeer)
  defer: peer.close() # No endpoint/callback borrows a header, receiver or complete canonical view after return.
  var active = default(DownloadAttempt)
  while true:
    let elapsed = (getMonoTime() - started).inMilliseconds
    if elapsed < 0: return RemoteAncestorResult(successful: false,
        refusal: CurrentDownloadCommandResult.DispatchFailure)
    let now = uint64(elapsed)
    if now >= timeout: return RemoteAncestorResult(successful: false,
        refusal: CurrentDownloadCommandResult.Timeout)
    owner.tick(0) # No candidate is queued: optional RPC/UI continue while context acquisition owns no worker lease.
    if not active.valid:
      let selection = schedule.select(DownloadScheduleTick(now))
      if selection.error == DownloadScheduleError.Exhausted:
        return RemoteAncestorResult(successful: false,
            refusal: CurrentDownloadCommandResult.Exhausted)
      if selection.error notin [DownloadScheduleError.None, DownloadScheduleError.Waiting]:
        return RemoteAncestorResult(successful: false,
            refusal: CurrentDownloadCommandResult.DispatchFailure)
      if selection.error == DownloadScheduleError.None:
        active = selection.value
        let ordinal = uint64(active.peer) # Command preflight constructed only fixed peer IDs 1..16.
        if ordinal == 0 or ordinal > uint64(peers.len):
          return RemoteAncestorResult(successful: false,
              refusal: CurrentDownloadCommandResult.DispatchFailure)
        let index = int(ordinal - 1)
        let duration = min(timeout - now, min(uint64(limits.attemptTimeout), uint64(
            limits.stream.timeout)))
        let streamLimits = AncestorStreamLimits(readBytes: limits.stream.readBytes,
          writeBytes: limits.stream.writeBytes, timeout: AncestorTimeout(duration))
        let opened = peer.open(request.value, limits.input.blockBytes,
          AncestorPeerKey(array[32, byte](keys[index])), ports[index], options.argument(3),
          options.argument(4), options.argument(6), streamLimits, AncestorTick(now))
        if opened != AncestorPeerError.None:
          peer.close()
          if schedule.finish(active, DownloadAttemptOutcome.Retry, DownloadScheduleTick(now)) !=
              DownloadScheduleError.None:
            return RemoteAncestorResult(successful: false,
                refusal: CurrentDownloadCommandResult.DispatchFailure)
          active = default(DownloadAttempt) # Failed setup consumes only its explicitly reserved finite attempt.
    if active.valid:
      let status = peer.tick(AncestorTick(now))
      if peer.stage == AncestorPeerStage.Ready:
        let decoded = peer.response(limits.candidate.reporting.admission.frame, headerBytes)
        peer.close() # Actual final native close and whole endpoint retirement precede retaining producer observations.
        if schedule.finish(active, DownloadAttemptOutcome.Retry, DownloadScheduleTick(now)) !=
            DownloadScheduleError.None:
          return RemoteAncestorResult(successful: false,
              refusal: CurrentDownloadCommandResult.DispatchFailure)
        active = default(DownloadAttempt)
        if decoded.error == AncestorResponseError.None:
          let fetched = decoded.value.headers
          var combined = newSeq[OwnedHeader](older.len + fetched.len)
          for index, header in older: combined[index] = header # Existing explicit/local context remains the newest prefix.
          for index, header in fetched: combined[older.len + index] = header
          if not ancestorsFit(head, combined, limits):
            return RemoteAncestorResult(successful: false,
                refusal: CurrentDownloadCommandResult.InvalidAncestors)
          return RemoteAncestorResult(successful: true, captured: combined)
        # Empty, structurally invalid, over-budget or wrong-lineage replies release their whole prefix and consume one attempt.
      elif status != AncestorPeerError.None:
        peer.close()
        if schedule.finish(active, DownloadAttemptOutcome.Retry, DownloadScheduleTick(now)) !=
            DownloadScheduleError.None:
          return RemoteAncestorResult(successful: false,
              refusal: CurrentDownloadCommandResult.DispatchFailure)
        active = default(DownloadAttempt) # Identity, reset and timeout failures cannot bypass the retry/cooldown ceiling.
    var requestedPause = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requestedPause, remaining) # Bounded nonblocking turns preserve service and peer progress.

type ObservedDownloadHead = object ## Fixed metadata survives joined shutdown without retaining a canonical ARC alias.
  initialized: bool
  hash: array[32, byte]
  slot: uint32

proc receiveChildren(owner: var Services, options: Options, peers: seq[DownloadPeerId],
    ports: array[16, uint16], keys: array[16, CurrentDownloadPeerKey], ancestors: seq[OwnedHeader],
    limits: CurrentDownloadLoopLimits, started: MonoTime, timeout: uint64, requested: int,
    adopted: var int, observed: var ObservedDownloadHead, qualifyLogical: bool,
    logical: CurrentLogicalDownloadPolicy): CurrentDownloadCommandResult {.raises.} =
  ## Stable endpoints outlive every retired child session; joined teardown precedes caller reconciliation on all exits.
  let initial = owner.chainView.bestBlock
  if initial.error != GenesisError.None: return CurrentDownloadCommandResult.AdmissionFailure
  observed = ObservedDownloadHead(initialized: true, hash: array[32, byte](initial.value.blockHash),
    slot: uint32(initial.value.slot))
  var previousHeader = initial.value.header
  var older = ancestors
  var remoteRemaining = uint64(options.discoverDownloadAncestors)
  var peersRetired = false
  if not ancestorsFit(previousHeader, older, limits): return CurrentDownloadCommandResult.AdmissionFailure
  var preflight = default(CurrentBlockDownload)
  let admitted = preflight.begin(owner, older, limits.input, limits.candidate)
  if admitted.error != CurrentBlockDownloadError.None: return CurrentDownloadCommandResult.AdmissionFailure
  discard preflight.cancel(admitted.value) # Exact raw admission is checked before any outgoing TLS engine opens.
  var dispatcher = default(CurrentDownloadLoop)
  defer: dispatcher.close() # Every native input/execution/disk borrower joins before outer canonical inspection or alias retirement.
  let configured = if qualifyLogical:
      dispatcher.configure(owner, peers, older, limits, CurrentDownloadLoopTick(0), logical)
    else: dispatcher.configure(owner, peers, older, limits, CurrentDownloadLoopTick(0))
  if configured != CurrentDownloadLoopError.None: return CurrentDownloadCommandResult.InvalidPolicy
  for index in 0..<peers.len:
    if dispatcher.openPeer(peers[index], keys[index], ports[index], options.argument(3),
        options.argument(4), options.argument(6)) != CurrentDownloadPeerError.None:
      return CurrentDownloadCommandResult.TransportFailure # Deferred close retires all earlier opened endpoints too.
  while true:
    let elapsed = (getMonoTime() - started).inMilliseconds
    if elapsed < 0: return CurrentDownloadCommandResult.DispatchFailure # Never narrow a broken clock into a huge deadline.
    if uint64(elapsed) >= timeout: return CurrentDownloadCommandResult.Timeout
    let ticked = dispatcher.tick(CurrentDownloadLoopTick(uint64(elapsed)))
    if ticked == CurrentDownloadLoopError.AttemptExpired: return CurrentDownloadCommandResult.Timeout
    if ticked != CurrentDownloadLoopError.None: return CurrentDownloadCommandResult.DispatchFailure
    case dispatcher.stage
    of CurrentDownloadLoopStage.Adopted:
      let confirmed = dispatcher.adoption
      let selected = owner.chainView.bestBlock # The actual adoption receipt has retired the exclusive worker lease.
      if confirmed.error != CurrentHandoffError.None or selected.error != GenesisError.None:
        return CurrentDownloadCommandResult.DispatchFailure
      let child = confirmed.value
      if array[32, byte](selected.value.blockHash) != array[32, byte](child.blockHash) or
          array[32, byte](child.parentHash) != observed.hash or uint32(child.slot) <= observed.slot:
        return CurrentDownloadCommandResult.DispatchFailure # Status cannot manufacture a canonical child or unrelated replacement.
      inc adopted
      observed = ObservedDownloadHead(initialized: true, hash: array[32, byte](child.blockHash),
          slot: uint32(child.slot))
      if owner.diskMaintenanceFailed: return CurrentDownloadCommandResult.StorageMaintenanceFailure
      if adopted == requested: return CurrentDownloadCommandResult.Adopted
      var next = newSeq[OwnedHeader](older.len + 1)
      next[0] = previousHeader
      for index, ancestor in older: next[index + 1] = ancestor # Whole-run count reservation proved this finite extent before startup.
      if not ancestorsFit(child.header, next, limits): return CurrentDownloadCommandResult.AdmissionFailure
      if dispatcher.nextChild(next, CurrentDownloadLoopTick(uint64(elapsed))) !=
          CurrentDownloadLoopError.None:
        return CurrentDownloadCommandResult.DispatchFailure
      if peersRetired:
        for index in 0..<peers.len:
          # Graceful discovery retirement preserved each fixed ID/key association; only the next child needs fresh endpoints.
          if dispatcher.openPeer(peers[index], keys[index], ports[index], options.argument(3),
              options.argument(4), options.argument(6)) != CurrentDownloadPeerError.None:
            return CurrentDownloadCommandResult.TransportFailure
        peersRetired = false
      previousHeader = child.header
      older = next # All ARC replacement occurs after collection/publication and before the next worker submission.
    of CurrentDownloadLoopStage.AwaitingAncestors:
      peersRetired = true # The dispatcher has joined its worker and gracefully retired every child connection.
      if remoteRemaining == 0: return CurrentDownloadCommandResult.Exhausted
      let demand = dispatcher.ancestorDemand
      if demand.error != CurrentDownloadSessionError.None: return CurrentDownloadCommandResult.DispatchFailure
      let maximum = demand.value.lookupDemandMaximum(ElementLimit(remoteRemaining))
      if maximum.error != ReportAnchorError.None or uint64(maximum.value) == 0:
        return CurrentDownloadCommandResult.InvalidAncestors
      let selected = owner.chainView.bestBlock
      if selected.error != GenesisError.None or array[32, byte](selected.value.blockHash) != observed.hash:
        return CurrentDownloadCommandResult.DispatchFailure # A changed canonical parent cannot authorize unrelated remote context.
      let now = uint64(elapsed)
      let duration = min(timeout - now, dispatcher.ancestorRemaining(CurrentDownloadLoopTick(now)))
      if duration == 0: return CurrentDownloadCommandResult.Timeout
      let deadline = now + duration # duration <= timeout-now proves addition cannot overflow or widen the command deadline.
      let before = older.len
      let acquired = remoteAncestors(owner, options, peers, ports, keys, older, limits, started,
        deadline, maximum.value)
      if not acquired.successful: return acquired.refusal
      let combined = acquired.captured
      if combined.len <= before or uint64(combined.len - before) > remoteRemaining:
        return CurrentDownloadCommandResult.InvalidAncestors # Every successful round must consume finite actual header progress.
      remoteRemaining -= uint64(combined.len - before)
      older = combined
      let resumedAt = (getMonoTime() - started).inMilliseconds
      if resumedAt < 0: return CurrentDownloadCommandResult.DispatchFailure
      if uint64(resumedAt) >= timeout: return CurrentDownloadCommandResult.Timeout
      let resumed = dispatcher.resumeAncestors(older, CurrentDownloadLoopTick(uint64(resumedAt)))
      if resumed == CurrentDownloadLoopError.AttemptExpired: return CurrentDownloadCommandResult.Timeout
      if resumed != CurrentDownloadLoopError.None: return CurrentDownloadCommandResult.DispatchFailure
    of CurrentDownloadLoopStage.Exhausted: return CurrentDownloadCommandResult.Exhausted
    of CurrentDownloadLoopStage.Failed: return CurrentDownloadCommandResult.DispatchFailure
    else: discard # Waiting/receiving/preparing/queued work requires a later bounded turn.
    var requestedPause = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requestedPause, remaining) # One bounded pause avoids spinning; endpoint polling remains nonblocking.

proc performDownloads(options: Options, adopted: var int): CurrentDownloadCommandResult {.raises.} =
  ## One Services owner retains every confirmed prefix; per-child barriers precede ancestry mutation and final shutdown joins.
  adopted = 0
  if not options.valid or options.argumentCount < 8 or
      options.argumentCount > 38 or (options.argumentCount - 8) mod 2 != 0 or options.argument(1) !=
          "download-current" or
      not options.stateEnabled or options.telemetryEnabled:
    return CurrentDownloadCommandResult.InvalidOptions # This command cannot silently discard requested outgoing telemetry.
  let timeout = number(options.argument(7), 120000)
  if timeout == 0: return CurrentDownloadCommandResult.InvalidEndpoint
  let policy = loadCurrentDownloadPolicy(options.argument(8))
  if policy.error != CurrentDownloadPolicyError.None: return CurrentDownloadCommandResult.InvalidPolicy
  let limits = policy.value
  let qualifyLogical = options.logicalDownloadEnabled
  var logicalLimits = default(CurrentLogicalStartupLimits)
  var declarations = default(CurrentLogicalDeclarations)
  if qualifyLogical:
    let configured = loadCurrentLogicalPolicy(options.logicalDownloadPolicyPath)
    if configured.error != CurrentDownloadPolicyError.None: return CurrentDownloadCommandResult.InvalidPolicy
    logicalLimits = configured.value
    let decoded = loadCurrentLogicalDeclarations(options.logicalDownloadSourcePath,
        logicalLimits.projection)
    if decoded.error != CurrentLogicalStartupError.None: return CurrentDownloadCommandResult.InvalidLogicalSource
    declarations = decoded.value # Full syntax/resource preflight precedes Services, listeners, databases and outgoing peers.
  if limits.input.discoverAncestors != (options.discoverDownloadAncestors > 0):
    return CurrentDownloadCommandResult.InvalidPolicy # Both explicit current policy and requested acquisition mode must agree.
  let count = 1 + (options.argumentCount - 8) div 2
  if uint64(count) > uint64(limits.schedule.peers): return CurrentDownloadCommandResult.InvalidPolicy
  var ports = default(array[16, uint16])
  var keys = default(array[16, CurrentDownloadPeerKey])
  var peers: seq[DownloadPeerId] = @[]
  for index in 0..<count:
    # The original tuple supplies credentials shared by every additional PORT PEER pair.
    let portArgument = if index == 0: 2 else: 9 + (index - 1) * 2
    let peerArgument = if index == 0: 5 else: portArgument + 1
    let port = number(options.argument(portArgument), 65535)
    if port == 0: return CurrentDownloadCommandResult.InvalidEndpoint
    ports[index] = uint16(port)
    if not identity(options.argument(peerArgument), keys[index]):
      return CurrentDownloadCommandResult.InvalidIdentity # No listener starts after a partially validated list.
    for previous in 0..<index:
      if keys[previous] == keys[index]: return CurrentDownloadCommandResult.InvalidIdentity # Aliases cannot multiply scheduler weight.
      if ports[previous] == ports[index]: return CurrentDownloadCommandResult.InvalidEndpoint # One loopback endpoint has one configured principal.
    peers.add(DownloadPeerId(uint64(index + 1))) # The shape cap proves IDs 1..16 and all argument arithmetic.
  let paths = options.ancestorPaths
  let ancestry = limits.candidate.reporting.reports.ancestors
  let requested = options.downloadBlocks
  let remote = uint64(options.remoteDownloadAncestors) + uint64(options.discoverDownloadAncestors)
  if remote > 0 and uint64(limits.input.blockBytes) > uint64(high(uint32)):
    return CurrentDownloadCommandResult.InvalidPolicy # Remote E4 response claims have a fixed u32 extent before any file or Services IO.
  let retained = uint64(paths.len) + remote + uint64(requested -
      1) # Parser caps both operands, independently of wrapping arithmetic.
  if retained > uint64(limits.input.ancestors) or retained >= uint64(ancestry.headers):
    return CurrentDownloadCommandResult.InvalidPolicy # Reserve the whole finite lineage, including each future selected parent, before file/Services IO.
  let loaded = loadAncestorInputs(paths, ancestry.header, limits.input.ancestors,
    ByteLimit(min(uint64(limits.input.ancestorBytes), uint64(ancestry.maxBytes))))
  if loaded.error != AncestorInputError.None:
    return CurrentDownloadCommandResult.InvalidAncestors # No Services/listener/database/outgoing TLS work follows partial capture.
  var ancestors = loaded.headers
  var owner = default(Services)
  defer: owner.close() # Dispatcher teardown below must end every Services borrow first.
  if not owner.start(options, "download-current"): return CurrentDownloadCommandResult.StartupFailure
  var logical = default(CurrentLogicalDownloadPolicy)
  if qualifyLogical:
    let captured = captureCurrentLogicalStartup(owner.chainView, declarations, logicalLimits)
    if captured.error != CurrentLogicalStartupError.None: return CurrentDownloadCommandResult.InvalidLogicalSource
    logical = captured.value # Full actual selected map/history/Parameters qualification precedes outgoing child peers.
  let started = getMonoTime()
  if options.localDownloadAncestors:
    # Capture before any worker lease; no complete view/map alias survives into receiveChildren.
    let combined = prependLocalAncestors(owner.chainView, ancestors, ancestry.header,
      limits.input.ancestors, ByteLimit(min(uint64(limits.input.ancestorBytes), uint64(
          ancestry.maxBytes))))
    if combined.error != AncestorInputError.None: return CurrentDownloadCommandResult.InvalidAncestors
    ancestors = combined.headers
    let reserved = uint64(ancestors.len) + remote + uint64(requested - 1)
    if reserved > uint64(limits.input.ancestors) or reserved >= uint64(ancestry.headers):
      return CurrentDownloadCommandResult.InvalidPolicy # Entire local suffix plus future parents must fit before outgoing transport.
  if options.remoteDownloadAncestors > 0:
    let acquired = remoteAncestors(owner, options, peers, ports, keys, ancestors, limits, started,
      timeout,
      ElementLimit(options.remoteDownloadAncestors))
    if not acquired.successful: return acquired.refusal # No child request follows a failed/partial ancestry capture.
    ancestors = acquired.captured
  var observed = default(ObservedDownloadHead)
  let terminal = receiveChildren(owner, options, peers, ports, keys, ancestors, limits,
    started, timeout, requested, adopted, observed, qualifyLogical, logical)
  if observed.initialized:
    let settled = owner.chainView.bestBlock # Joined shutdown may confirm an IO receipt after the command reached its deadline.
    if settled.error != GenesisError.None: return CurrentDownloadCommandResult.DispatchFailure
    if array[32, byte](settled.value.blockHash) != observed.hash:
      if adopted >= requested or array[32, byte](settled.value.parentHash) != observed.hash or
          uint32(settled.value.slot) <= observed.slot:
        return CurrentDownloadCommandResult.DispatchFailure # Only this run's one outstanding child can add shutdown-confirmed progress.
      inc adopted
  if owner.diskMaintenanceFailed: return CurrentDownloadCommandResult.StorageMaintenanceFailure
  terminal

proc runCurrentDownloads*(options: Options): CurrentDownloadCommandOutcome {.raises.} =
  ## Report confirmed scalar progress after Services/worker teardown; failure does not imply rollback of its prefix.
  var adopted = 0
  let terminal = performDownloads(options, adopted)
  CurrentDownloadCommandOutcome(status: terminal, requested: options.downloadBlocks,
      adopted: adopted)

proc runCurrentDownload*(options: Options): CurrentDownloadCommandResult {.raises.} =
  ## Preserve the original status-only API; callers needing partial progress use runCurrentDownloads.
  runCurrentDownloads(options).error
