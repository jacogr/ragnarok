# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordinary authenticated full-state node loop with explicitly trusted local finality.
## Stable actor storage retires before Services; wall-clock authority never comes from peers.
import std/[monotimes, times, syncio, strutils]
import ./[options, services, node as application_node]
import ./cli/commands
import ./proof/ticket_production
import ./[work_dispatch, work_policy, node_work_policy, node_assurance_policy]
import ./proof/[worker, assurance_storage]
import ../jamnp-s/[assurance_store, assurance_record]
import ../crypto/primitives
import ../jamnp-s/[connections, node as node_streams]
import ../chain/[provider, genesis, parameters]
import ../codec/[bounded, header, assurances, tickets]
import ../quic/address
import ../codec/state/[safrole, consensus]
import ../lib/[logging, stop_signal]

type
  NodeCommandError* {.pure.} = enum ## Only Stopped denotes completed signal/deadline shutdown; setup failures grant no running node.
    Uninitialized, Stopped, InvalidConfig, StartupFailure, UnknownFinality, InvalidSource,
    InvalidClock, NetworkFailure, InvalidSigner, InvalidWorkPolicy, InvalidAssurancePolicy
  NodeClockError* {.pure.} = enum ## Default and invalid clocks expose no narrowed timeslot.
    Uninitialized, None, BeforeCommonEra, InvalidPeriod, Overflow
  NodeClockResult* = object ## A successful complete conversion alone grants the local JAM timeslot.
    case status: NodeClockError
    of None: slot: StateTime
    else: discard           # No fallback clock/time is carried by a refusal.

const JamCommonEraUnix* = 1735732800'i64 ## Pinned GP Overview:1200 UTC January1,2025.

func error*(clock: NodeClockResult): NodeClockError =
  ## Read a failed conversion without extracting a default timeslot.
  clock.status
func value*(clock: NodeClockResult): StateTime {.requires: clock.status == NodeClockError.None.} =
  ## Only an admitted unsigned32-bit slot can reach connectivity epoch timing.
  clock.slot
func nodeClock*(unixSeconds: int64, secondsPerSlot: uint64): NodeClockResult =
  ## Subtract only after proving the common-era lower bound and narrow only after the slot ceiling.
  if secondsPerSlot == 0: return NodeClockResult(status: NodeClockError.InvalidPeriod)
  if unixSeconds < JamCommonEraUnix: return NodeClockResult(status: NodeClockError.BeforeCommonEra)
  let elapsed = uint64(unixSeconds-JamCommonEraUnix)
  let slot = elapsed div secondsPerSlot
  if slot > uint64(high(uint32)): return NodeClockResult(status: NodeClockError.Overflow)
  NodeClockResult(status: NodeClockError.None, slot: StateTime(uint32(slot)))
proc configuration(options: Options, finalized: var BlockHash, port: var uint16,
    timeout: var uint64): bool =
  ## Revalidate private canonical argument shapes before filesystem/native setup, even for internal callers.
  finalized = default(BlockHash)
  port = 0
  timeout = 0
  if not options.valid or not options.stateEnabled or options.lightMode: return false
  if options.argumentCount notin [6, 7, 8, 10] or options.argument(1) != "node": return false
  if options.argumentCount >= 7:
    let path = options.argument(7)
    if path.len > 4096 or path.find(char(0)) >= 0: return false
    if path.len == 0 and options.argumentCount == 7: return false
  if options.argumentCount >= 8:
    let path = options.argument(8)
    if path.len > 4096 or path.find(char(0)) >= 0: return false
    if options.argumentCount == 8 and path.len == 0: return false
  if options.argumentCount == 10:
    for ordinal in 9..10:
      let path = options.argument(ordinal)
      if path.len == 0 or path.len > 4000 or path.find(char(0)) >= 0: return false
    if options.argument(10)[options.argument(10).len-1] == '/': return false
  var number = 0'u64
  if not unsignedValue(options.argument(2), number) or number < 1 or number > 65535: return false
  port = uint16(number)
  if not unsignedValue(options.argument(6), timeout) or timeout > uint64(
      MaxPeerTimeoutMs): return false
  let text = options.argument(5)
  if text.len != 64: return false
  var hash = default(array[32, byte])
  for index, character in text:
    var nibble = 0'u8
    if character in {'0'..'9'}: nibble = byte(ord(character)-ord('0'))
    elif character in {'a'..'f'}: nibble = byte(ord(character)-ord('a')+10)
    else: return false # One documented lower-case config representation; no prefix/width fallback.
    hash[index div 2] = (hash[index div 2] shl 4) or nibble
  finalized = BlockHash(hash)
  true
proc policy(services: Services, limits: var SafroleStateConfig, period: var uint64): bool =
  ## Retire temporary canonical aliases before the loop can admit any worker or native callback.
  limits = default(SafroleStateConfig)
  period = 0
  let head = services.chainView.bestBlock
  if head.error != GenesisError.None: return false
  let profile = head.value.chainParameters
  if not profile.valid: return false
  let cores = profile.get(coreCount)
  let epoch = profile.get(epochPeriod)
  if cores < 2 or cores > 341 or epoch == 0 or epoch > 4096: return false
  period = profile.get(slotPeriodSec)
  if period == 0: return false
  limits = SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(cores),
    validators: ElementLimit(cores*3), maxBytes: ByteLimit(1048576)),
    epochSlots: EpochSlots(epoch), maxAccumulator: ElementLimit(4096), maxBytes: ByteLimit(1048576))
  true
proc configureSignerFile(services: var Services, path: string): bool {.raises.} =
  ## Explicit optional input reads at most33 bytes and wipes all borrowed seed storage on every return/exception path.
  var seed = default(array[33, byte])
  defer: clearSecret(seed)
  try:
    var input = default(File)
    if not open(input, path, fmRead): return false
    defer: close(input)
    let count = readBuffer(input, addr seed[0], seed.len)
    if count != 32: return false # Short and suffixed inputs cannot silently select a different signing identity.
    return services.configureTicketSignerSeed(seed.toOpenArray(0, 31)).error ==
        TicketSignerError.None
  except:
    return false # The typed command outcome reports local configuration failure without exposing file or key contents.
proc pauseStartup(microseconds: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Startup yields only through the platform OS; all JAM policy and worker ownership remain in Nim.
proc configureAssurances(host: var ApplicationNode, services: var Services,
    policy: NodeAssurancePolicy, folder, certificate, privateKey: string,
    signals: var StopSignals): bool {.raises.} =
  ## A finite explicit namespace job is joined/collected before importing keys or activating network controllers; any refusal requires closing the enclosing startup owner.
  if not host.isValidator: return false # Reject an observer before namespace creation or private import.
  let opening = services.beginAssuranceStorage(folder, policy.storageLimits, policy.storageMode)
  if opening.error != AssuranceStorageStartError.None: return false
  let ticket = opening.value
  var active = true
  defer:
    if active and services.stateProofActive(ticket): services.stopStateProofs()
  let started = getMonoTime()
  while services.stateProofPhase != ProofWorkerPhase.Done:
    if signals.stopping or uint64((getMonoTime()-started).inMilliseconds) >=
        policy.startupTimeoutMs:
      return false # The defer joins this exact owned namespace operation without abandoning borrowed storage.
    discard pauseStartup(1000)
  let completed = services.collectStateProof(ticket)
  active = false
  if completed.kind != ProofWorkerCompletionKind.AssuranceCompleted: return false
  if completed.assuranceStorageValue.error != AssuranceStoreError.None: return false
  if not host.configureAssuranceSigner(certificate, privateKey): return false
  if not services.configureAssuranceReads(policy.readLimits): return false
  if not host.configureAssuranceAcquisition(policy.acquisitionPolicy): return false
  if not host.configureAssuranceReceipt(policy.receiptPolicy): return false
  return host.configureAssuranceBroadcast(policy.broadcastPolicy)
proc runNodeCommand*(options: Options): NodeCommandError {.raises.} =
  ## One foreground owner polls authenticated topology/UP0/reads with optional services until signal or finite deadline.
  var finalized = default(BlockHash)
  var port = 0'u16
  var timeout = 0'u64
  if not configuration(options, finalized, port, timeout): return NodeCommandError.InvalidConfig
  var workPolicy = default(NodeWorkPolicy)
  if options.argumentCount >= 8 and options.argument(8).len > 0:
    let loaded = loadNodeWorkPolicy(options.argument(8), options.logWriter)
    if loaded.error != WorkPolicyError.None:
      log(options.logWriter, LogTarget.Startup, LogLevel.Error,
        "Invalid node work policy: " & $loaded.error & "; field=" & loaded.fieldName)
      return NodeCommandError.InvalidWorkPolicy
    workPolicy = loaded.value # Complete policy parsing precedes Services, sockets and optional private signer loading.
  var assurancePolicy = default(NodeAssurancePolicy)
  if options.argumentCount == 10:
    let loaded = loadNodeAssurancePolicy(options.argument(9))
    if loaded.error != WorkPolicyError.None:
      log(options.logWriter, LogTarget.Startup, LogLevel.Error,
        "Invalid node assurance policy: " & $loaded.error & "; field=" & loaded.fieldName)
      return NodeCommandError.InvalidAssurancePolicy
    assurancePolicy = loaded.value # Whole file validation precedes Services, sockets, archive operations and private imports.
  var signals = default(StopSignals)
  signals.start()
  defer: signals.close() # Keep handlers installed through every native close and joined worker teardown.
  var services = default(Services)
  defer: services.close()
  if not services.start(options, "node"): return NodeCommandError.StartupFailure
  if options.argumentCount >= 7 and options.argument(7).len > 0:
    if not services.configureSignerFile(options.argument(7)): return NodeCommandError.InvalidSigner
  if services.publishFinalized(finalized) != ViewFinalizeError.None:
    return NodeCommandError.UnknownFinality # Neither best nor recovered startup state silently supplies trusted finality.
  var limits = default(SafroleStateConfig)
  var period = 0'u64
  if not services.policy(limits, period): return NodeCommandError.InvalidSource
  if assurancePolicy.valid and not assurancePolicy.matches(limits, period):
    return NodeCommandError.InvalidAssurancePolicy # An explicit profile must match the actual complete source before disk activation.
  let selectedAlpn = services.nodeProtocol
  if selectedAlpn.len == 0 or services.networkProtocol(options) != selectedAlpn:
    return NodeCommandError.InvalidConfig # A node uses configured-genesis base ALPN; builder acceptor support remains in its connection owner.
  let initial = nodeClock(getTime().toUnix, period)
  if initial.error != NodeClockError.None: return NodeCommandError.InvalidClock
  let binding = options.networkBind
  let ipv6 = binding.valid and binding.ipv6
  let config = initConnectionConfig(options.argument(3), options.argument(4), selectedAlpn, port,
    binding, streams = 16384)
  var host = default(ApplicationNode)
  defer: host.close() # Native callbacks and this host's exact worker lease retire before borrowed Services storage.
  if host.open(services, config, limits, initial.value) != NodeError.None:
    return NodeCommandError.NetworkFailure
  if workPolicy.valid:
    let configured = host.configureNodeWork(workPolicy, options.argument(3), options.argument(4))
    if configured != NodeWorkSetupError.None:
      log(options.logWriter, LogTarget.Startup, LogLevel.Error, "Node work setup refused: " & $configured)
      return NodeCommandError.InvalidWorkPolicy
  if assurancePolicy.valid:
    if not configureAssurances(host, services, assurancePolicy, options.argument(10),
        options.argument(3), options.argument(4), signals):
      return NodeCommandError.InvalidAssurancePolicy # Every partial startup path retires through the enclosing native/Services defers.
  if not services.configureTelemetry(options, options.argument(3), host.localPort,
      ipv6): return NodeCommandError.StartupFailure
  log(options.logWriter, LogTarget.Network, LogLevel.Info,
    "Authenticated node listening on UDP port " & $host.localPort & "; protocol=" & selectedAlpn)
  let started = getMonoTime()
  var previous = initial.value
  while not signals.stopping:
    let clock = getMonoTime()
    if timeout > 0 and uint64((clock-started).inMilliseconds) >= timeout:
      break # Zero denotes a foreground lifetime; a positive bound always uses the monotonic clock.
    let unixSeconds = getTime().toUnix
    let now = nodeClock(unixSeconds, period)
    if now.error != NodeClockError.None: return NodeCommandError.InvalidClock
    if uint32(now.value) < uint32(previous): return NodeCommandError.InvalidClock
    previous = now.value
    let assuranceNow = AssuranceTime(uint64(unixSeconds-JamCommonEraUnix))
    if not host.poll(clock, now.value, assuranceNow, 1): return NodeCommandError.NetworkFailure
    services.tick(uint32(host.peerCount)) # Canonical work stays behind Services' existing exact ownership gates.
  NodeCommandError.Stopped
