# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit JAM_FUZZ startup runs only ephemeral full-state sessions with host-supplied Parameters and execution policy.
import ../lib/logging as lib_logging

from ./cli_defaults as app_cli_defaults import DefaultFuzzWrites, DefaultFuzzWriteBytes

import std/assertions
import std/atomics
import std/envvars
import std/monotimes
import std/os
import std/syncio
import std/posix/posix
import ../pvm/backend as pvm_backend
import ./fuzz_socket as app_fuzz_socket
import ./fuzz_backend as app_fuzz_backend
import ./fuzz_rejection as app_fuzz_rejection
import ./current_download_policy as app_current_download_policy
import ./candidate as app_candidate
import ./fuzz_policy as app_fuzz_policy
import ../chain/parameters as chain_parameters
import ../chain/presets as chain_presets
import ../chain/genesis as chain_genesis
import ../codec/bounded as codec_bounded
import ../codec/block_codec as codec_block_codec
import ../state/fuzz_protocol as state_fuzz_protocol
import ../state/fuzz_session as state_fuzz_session
import ../state/store as state_store
import ../management/file_status as management_file_status
import ../lib/atomic_file as lib_atomic_file
from ../rpc/protocol as rpc_protocol import configuredParameters

type
  FuzzEnvironment* = object ## Standard target entry variables are copied once before listener startup.
    enabled*: bool
    spec*, dataPath*, socketPath*, logLevel*: string
  FuzzTargetConfig* = object ## Plain configuration owns no native resources or production chain authority.
    socket*: FuzzSocketConfig
    backend*: FuzzBackendConfig
    dataPath*: string
  FuzzTargetError* {.pure.} = enum ## Startup failures expose no partially configured listener or seed.
    Uninitialized, None, MissingEnvironment, InvalidSpec, InvalidLogLevel, InvalidPath,
      InvalidPolicy, ProfileMismatch, InvalidBudget
  FuzzTargetResult* = object ## Complete startup policy is separate from the selected failure reason.
    case status: FuzzTargetError
    of None: config: FuzzTargetConfig
    else: discard            # Invalid input cannot expose a successful configuration prefix.
  SignalHandler = proc(number: cint) {.cdecl.} ## The C ABI owns handler invocation and previous-handler identity.

let
  InterruptSignal {.importc: "SIGINT", header: "<signal.h>".}: cint
  TerminateSignal {.importc: "SIGTERM", header: "<signal.h>".}: cint

var stopFlag: cint = 0 ## Only scalar lock-free atomic operations access this process-wide signal flag.
proc stopRequested(number: cint) {.cdecl.} =
  ## No allocation, logging, IO or ARC operation occurs in signal context.
  atomicStore(stopFlag, 1)
proc installSignal(number: cint, handler: SignalHandler): SignalHandler {.importc: "signal",
    header: "<signal.h>".}
  ## Restore each original process handler before returning from the dedicated target command.
proc effectiveUid(): uint32 {.importc: "geteuid", header: "<unistd.h>".}
  ## Runtime data paths must belong to the effective user.
func error*(outcome: FuzzTargetResult): FuzzTargetError =
  ## Read only the immutable selected startup reason.
  outcome.status
func value*(outcome: FuzzTargetResult): FuzzTargetConfig {.inline,
    requires: outcome.status == FuzzTargetError.None.} =
  ## Extract the complete detached policy only after successful startup validation.
  outcome.config
func pathValid(path: string): bool =
  ## Keep bounded absolute native paths free of NUL/control truncation.
  if path.len == 0 or path.len > 1024 or path[0] != '/': return false
  for c in path:
    if ord(c) < 32 or ord(c) == 127: return false # No hidden native pathname suffix can be ignored.
  true
proc prepareFuzzTarget*(environment: FuzzEnvironment, parameters: Parameters,
    candidate: CurrentCandidateLimits, writes: ElementLimit,
        writeBytes: ByteLimit): FuzzTargetResult =
  ## Match explicit tiny/full/fuzz domains without deriving Parameters from a peer or arbitrary seed map.
  if not environment.enabled or environment.spec.len == 0 or environment.dataPath.len == 0 or
      environment.socketPath.len == 0: return FuzzTargetResult(
          status: FuzzTargetError.MissingEnvironment)
  if environment.spec notin ["tiny", "full", "fuzz"]: return FuzzTargetResult(
      status: FuzzTargetError.InvalidSpec)
  if environment.logLevel notin ["", "error", "warn", "info", "debug", "trace"]:
    return FuzzTargetResult(status: FuzzTargetError.InvalidLogLevel)
  if not pathValid(environment.dataPath) or not pathValid(environment.socketPath) or
      environment.socketPath.len > 103:
    return FuzzTargetResult(status: FuzzTargetError.InvalidPath)
  if uint64(writes) > 1000000 or uint64(writeBytes) > 67108864:
    return FuzzTargetResult(status: FuzzTargetError.InvalidBudget)
  let frame = candidate.reporting.admission.frame
  let preset = if environment.spec == "tiny": ChainPreset.Tiny elif environment.spec ==
      "fuzz": ChainPreset.Fuzz else: ChainPreset.Full
  let canonical = presetParameters(preset)
  if not canonical.ok: return FuzzTargetResult(status: FuzzTargetError.ProfileMismatch)
  let expected = canonical.value
  let cores = expected.get(coreCount)
  let slots = expected.get(epochPeriod)
  let validators = cores * 3
  var selectedParameters = parameters
  let parameterMatch = parameters.valid and parameters.get(coreCount) == cores and
      parameters.get(epochPeriod) == slots
  let frameMatch = uint64(frame.cores) == cores and uint64(frame.epochSlots) == slots and
      uint64(frame.validators) == validators
  if not parameterMatch or not frameMatch:
    return FuzzTargetResult(status: FuzzTargetError.ProfileMismatch)
  if environment.spec == "fuzz":
    # Issue215 changes exactly nine Full constants; require the complete trusted tuple, not only geometry.
    for field in low(Parameter)..high(Parameter):
      # The canonical catalog owns all scalars; independent fixtures verify their values separately.
      if parameters.get(field) != expected.get(field):
        return FuzzTargetResult(status: FuzzTargetError.ProfileMismatch)
    selectedParameters = expected # Preserve explicit D900 interpretation throughout every retained snapshot.
    # Policy-owned consensus constants must agree with Parameters; resource ceilings remain separate local limits.
    if uint64(frame.ticketLimit) != expected.get(maxTicketsPerBlock) or
        uint64(candidate.reporting.safrole.blockTickets) != expected.get(maxTicketsPerBlock) or
        uint64(candidate.reporting.safrole.tailStart) != expected.get(epochTailStart) or
        uint64(candidate.reporting.reports.credentials.assignments.rotationSlots) != expected.get(
            rotationPeriod) or
        uint64(candidate.reporting.reports.anchors.lookupAge) != expected.get(maxLookupAnchorAge) or
        uint64(candidate.reporting.reports.policy.reportGas) != expected.get(maxAccumulateGas) or
        uint64(candidate.round.reportGas) != expected.get(maxAccumulateGas) or uint64(
            candidate.round.blockGas) != expected.get(blockGasLimit):
      return FuzzTargetResult(status: FuzzTargetError.ProfileMismatch)
  var state = genesisStoreLimits()
  state.writes = writes
  state.writeValueBytes = writeBytes
  let wire = FuzzLimits(bytes: ByteLimit(16777216), text: ByteLimit(4096), state: state, frame: frame)
  let backend = FuzzBackendConfig(parameters: selectedParameters, candidate: candidate, wire: wire,
      initialAncestry: true, forkStates: ElementLimit(8))
  if initFuzzBackend(backend).error != FuzzBackendError.None:
    return FuzzTargetResult(status: FuzzTargetError.InvalidPolicy)
  let peer = FuzzPeer(protocol: 1, features: 3, jam: FuzzVersion(major: 0, minor: 8, patch: 0),
      name: "Ragnarok")
  FuzzTargetResult(status: FuzzTargetError.None, config: FuzzTargetConfig(
    socket: FuzzSocketConfig(path: environment.socketPath, timeoutMs: 30000, peer: peer,
        limits: wire),
    backend: backend, dataPath: environment.dataPath))
proc text(bytes: openArray[byte]): string =
  ## Copy bounded configuration bytes without altering their JSON/policy representation.
  result = newString(bytes.len)
  for index, octet in bytes: result[index] = char(octet) # Complete input extent bounds every output assignment.
proc budget(text: string, maximum: uint64, value: var uint64): bool =
  ## Parse a canonical unsigned bounded count before multiply/add can wrap.
  value = 0
  if text.len == 0 or text.len > 20 or (text.len > 1 and text[0] == '0'): return false
  for c in text:
    if c notin {'0'..'9'}: return false # No signs, separators or exponent spellings.
    let digit = uint64(ord(c)-ord('0'))
    if value > (maximum-digit) div 10: return false
    value = value*10+digit
  value <= maximum
proc createNativeDirectory(path: cstring, mode: Mode): cint {.importc: "mkdir",
    header: "<sys/stat.h>".}
  ## The native binary creates selected runtime paths without a shell or external process.
proc directoryStatus(path: cstring, status: var FileStatus): cint {.importc: "stat",
    header: "<sys/stat.h>".}
  ## Ancestor lookup follows ordinary OS aliases such as macOS /tmp; the selected leaf is checked separately.
proc ensureDirectory(path: string, depth: int): bool =
  ## Bounded recursive parent creation uses0700 from the first visible inode; existing parents stay unchanged.
  if depth > 512 or not pathValid(path): return false
  var nativePath = path
  var status = default(FileStatus)
  if directoryStatus(nativePath.toCString(), status) == 0: return S_ISDIR(Mode(status.st_mode))
  let parent = parentDir(path)
  if parent == path or not ensureDirectory(parent, depth+1): return false
  createNativeDirectory(nativePath.toCString(), Mode(0o700)) == 0
proc prepareDirectory(path: string): bool =
  ## Only explicitly selected, runtime-owned non-symlink directories may become private startup storage.
  if not ensureDirectory(path, 0): return false
  var nativePath = path
  var status = default(FileStatus)
  if readStatus(nativePath.toCString(), status) != 0 or not S_ISDIR(Mode(status.st_mode)) or
      uint32(status.st_uid) != effectiveUid(): return false
  chmod(nativePath.toCString(), Mode(0o700)) == 0
proc resolveFuzzEnvironment*(base: FuzzEnvironment, overrides: openArray[string],
    environment: var FuzzEnvironment): bool =
  ## Merge explicit pairs over a captured environment; malformed pairs expose no partial configuration.
  environment = default(FuzzEnvironment)
  var selected = base
  if overrides.len mod 2 != 0: return false
  var index = 0
  while index < overrides.len:
    let value = overrides[index+1]
    if value.len == 0: return false
    case overrides[index]
    of "--fuzz-spec": selected.spec = value
    of "--fuzz-data-path": selected.dataPath = value
    of "--fuzz-sock-path": selected.socketPath = value
    of "--fuzz-log-level": selected.logLevel = value
    else: return false # Only catalog-approved environment equivalents belong to this boundary.
    index += 2
  environment = selected
  true

proc runFuzzTarget*(arguments: openArray[string], logging: LogWriter = default(
    LogWriter), selected: PvmBackend = DefaultPvmBackend): int {.raises.} =
  ## The ordinary executable selects conformance mode from standard environment variables and owns the complete startup lifecycle.
  let automatic = arguments.len == 0
  let builtIn = automatic or (arguments.len >= 3 and arguments[0] == "fuzz")
  let namedPreset = builtIn or (arguments.len >= 4 and arguments[0] == "serve-fuzz-preset")
  let captured = FuzzEnvironment(enabled: automatic and existsEnv("JAM_FUZZ") or not automatic,
      spec: getEnv("JAM_FUZZ_SPEC"),
    dataPath: getEnv("JAM_FUZZ_DATA_PATH"), socketPath: getEnv("JAM_FUZZ_SOCK_PATH"),
    logLevel: getEnv("JAM_FUZZ_LOG_LEVEL"))
  var policyPath = ""
  var parameterPath = ""
  var writeText = $DefaultFuzzWrites
  var byteText = $DefaultFuzzWriteBytes
  var overrideStart = 0
  if automatic:
    discard # The public conformance contract needs only upstream environment variables and built-in policy.
  elif builtIn:
    writeText = arguments[1]
    byteText = arguments[2]
    overrideStart = 3
  elif namedPreset or (arguments.len >= 5 and arguments[0] == "serve-fuzz"):
    # Internal explicit-policy regression callers retain their established positional contract.
    policyPath = arguments[1]
    let offset = if namedPreset: 2 else: 3
    if not namedPreset: parameterPath = arguments[2]
    writeText = arguments[offset]
    byteText = arguments[offset+1]
    overrideStart = offset+2
  else:
    stderr.writeLine("FUZZ_START_FAILED arguments")
    return 2
  var environment = default(FuzzEnvironment)
  var overrides: seq[string] = @[]
  for index in overrideStart..<arguments.len: overrides.add(arguments[index])
  if not resolveFuzzEnvironment(captured, overrides, environment):
    stderr.writeLine("FUZZ_START_FAILED environment overrides")
    return 2
  var writes = 0'u64
  var writeBytes = 0'u64
  if not budget(writeText, 1000000, writes) or not budget(byteText, 67108864, writeBytes):
    stderr.writeLine("FUZZ_START_FAILED policy or budget")
    return 2
  var preset = ChainPreset.Tiny
  case environment.spec
  of "tiny": preset = ChainPreset.Tiny
  of "full": preset = ChainPreset.Full
  of "fuzz": preset = ChainPreset.Fuzz
  else:
    stderr.writeLine("FUZZ_START_FAILED InvalidSpec")
    return 2
  var policy = fuzzPresetPolicy(preset)
  if not builtIn:
    # Explicit test-host overrides remain bounded; public conformance launch needs no policy file.
    let loadedPolicy = readBoundedFile(policyPath, ByteLimit(CurrentDownloadPolicyBytes))
    if loadedPolicy.error != AtomicFileError.None:
      stderr.writeLine("FUZZ_START_FAILED configuration files")
      return 2
    policy = decodeCurrentDownloadPolicy(text(loadedPolicy.value))
  var parameters = unavailableParameters()
  if namedPreset:
    # Select immutable catalog parameters before reading any seed supplied over the socket.
    case environment.spec
    of "tiny": parameters = presetParameters(ChainPreset.Tiny)
    of "full": parameters = presetParameters(ChainPreset.Full)
    of "fuzz": parameters = presetParameters(ChainPreset.Fuzz)
    else: discard # Invalid/missing selection cannot expose a default successful tuple.
  else:
    # Existing explicit custom Tiny/Full host configurations remain supported.
    let loadedParameters = readBoundedFile(parameterPath, ByteLimit(8388608))
    if loadedParameters.error != AtomicFileError.None: return 2
    parameters = configuredParameters(text(loadedParameters.value))
  if policy.error != CurrentDownloadPolicyError.None or not parameters.ok:
    stderr.writeLine("FUZZ_START_FAILED configuration encoding")
    return 2
  var candidate = policy.value.candidate
  candidate.selectLogging(logging)
  candidate.selectPvmBackend(selected)
  let prepared = prepareFuzzTarget(environment, parameters.value, candidate,
      ElementLimit(writes), ByteLimit(writeBytes))
  if prepared.error != FuzzTargetError.None:
    stderr.writeLine("FUZZ_START_FAILED " & $prepared.error)
    return 2
  let config = prepared.value
  if not prepareDirectory(config.dataPath) or not prepareDirectory(parentDir(config.socket.path)):
    stderr.writeLine("FUZZ_START_FAILED private runtime directories")
    return 2
  var server = default(FuzzSocket)
  if not server.start(config.socket):
    stderr.writeLine("FUZZ_START_FAILED socket")
    return 2
  atomicStore(stopFlag, 0)
  let previousInt = installSignal(InterruptSignal, stopRequested)
  let previousTerm = installSignal(TerminateSignal, stopRequested)
  try:
    var generation = 0'u64
    var backend = initFuzzBackend(config.backend).value
    stdout.writeLine("FUZZ_READY protocol=1 gp=0.8.0 features=3")
    stdout.flushFile()
    while atomicLoad(stopFlag) == 0:
      server.tick() # IO is bounded and never executes a guest inside its callback.
      if server.connected and server.generation != generation:
        backend = initFuzzBackend(config.backend).value
        generation = server.generation # Every accepted connection discards the prior session's complete seed and history.
      if server.hasRequest:
        let ticket = server.request
        let message = ticket.requestMessage.value
        if message.fuzzInfo.value.kind == FuzzKind.Initialize:
          var selected = config.backend
          if (server.negotiatedFeatures and 1'u32) == 0: selected.initialAncestry = false
          if (server.negotiatedFeatures and 2'u32) == 0: selected.forkStates = ElementLimit(0)
          backend = initFuzzBackend(selected).value # No unnegotiated fork behavior survives initialization.
        let outcome = backend.executeFuzz(message) # Synchronous bounded-by-policy STF belongs outside socket IO.
        if outcome.error == FuzzBackendError.None:
          discard server.respond(ticket, outcome.value)
        elif outcome.error == FuzzBackendError.CandidateFailure and consensusFuzzRejection(
            outcome.candidateFailure):
          let reply = newFuzzError("ImportBlock rejected", config.backend.wire)
          if reply.error != FuzzError.None or not server.respond(ticket,
              reply.value): server.disconnect()
        else:
          var reason = $outcome.error
          if outcome.error == FuzzBackendError.CandidateFailure:
            reason &= " " & localFuzzCandidateReason(outcome.candidateFailure)
          elif outcome.error == FuzzBackendError.AncestryFailure:
            reason &= " " & $outcome.ancestryFailure
          stderr.writeLine("FUZZ_SESSION_FAILED " & reason)
          server.disconnect() # Internal/resource/context failures must not impersonate consensus Error responses.
      if not server.connected: backend = initFuzzBackend(
          config.backend).value # Retire any disconnected private seed promptly.
      sleep(1) # The dedicated test process has no public RPC, UI, QUIC or durable-state services to starve.
  finally:
    discard installSignal(InterruptSignal, previousInt)
    discard installSignal(TerminateSignal, previousTerm)
    server.close() # Native socket removal and ephemeral owners retire before normal process return.
  0
