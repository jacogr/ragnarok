# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit JAM_FUZZ startup runs only ephemeral full-state sessions with host-supplied Parameters and execution policy.
import std/[assertions, atomics, envvars, monotimes, os, syncio]
import std/posix/posix
import ./[fuzz_socket, fuzz_backend, fuzz_rejection, current_download_policy, candidate]
import ../chain/[parameters, genesis]
import ../codec/[bounded, block_codec]
import ../state/[fuzz_protocol, fuzz_session, store]
import ../management/file_status
import ../lib/atomic_file
from ../rpc/protocol import configuredParameters

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
  ## Match explicit tiny/full domains without deriving Parameters from a peer or arbitrary seed map.
  if not environment.enabled or environment.spec.len == 0 or environment.dataPath.len == 0 or
      environment.socketPath.len == 0: return FuzzTargetResult(
          status: FuzzTargetError.MissingEnvironment)
  if environment.spec notin ["tiny", "full"]: return FuzzTargetResult(
      status: FuzzTargetError.InvalidSpec)
  if environment.logLevel notin ["", "error", "warn", "info", "debug", "trace"]:
    return FuzzTargetResult(status: FuzzTargetError.InvalidLogLevel)
  if not pathValid(environment.dataPath) or not pathValid(environment.socketPath) or
      environment.socketPath.len > 103:
    return FuzzTargetResult(status: FuzzTargetError.InvalidPath)
  if uint64(writes) > 1000000 or uint64(writeBytes) > 67108864:
    return FuzzTargetResult(status: FuzzTargetError.InvalidBudget)
  let frame = candidate.reporting.admission.frame
  let cores = if environment.spec == "tiny": 2'u64 else: 341'u64
  let slots = if environment.spec == "tiny": 12'u64 else: 600'u64
  let validators = if environment.spec == "tiny": 6'u64 else: 1023'u64
  let parameterMatch = parameters.valid and parameters.get(coreCount) == cores and
      parameters.get(epochPeriod) == slots
  let frameMatch = uint64(frame.cores) == cores and uint64(frame.epochSlots) == slots and
      uint64(frame.validators) == validators
  if not parameterMatch or not frameMatch:
    return FuzzTargetResult(status: FuzzTargetError.ProfileMismatch)
  var state = genesisStoreLimits()
  state.writes = writes
  state.writeValueBytes = writeBytes
  let wire = FuzzLimits(bytes: ByteLimit(16777216), text: ByteLimit(4096), state: state, frame: frame)
  let backend = FuzzBackendConfig(parameters: parameters, candidate: candidate, wire: wire,
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
proc runFuzzTarget*(arguments: openArray[string]): int {.raises.} =
  ## Dedicated process mode accepts only explicit policy/parameter paths and write budgets; no production services start.
  if arguments.len != 5 or arguments[0] != "serve-fuzz":
    stderr.writeLine("FUZZ_START_FAILED arguments: serve-fuzz CURRENT_POLICY PARAMETERS_JSON MAX_WRITES MAX_WRITE_BYTES")
    return 2
  let environment = FuzzEnvironment(enabled: existsEnv("JAM_FUZZ"), spec: getEnv("JAM_FUZZ_SPEC"),
    dataPath: getEnv("JAM_FUZZ_DATA_PATH"), socketPath: getEnv("JAM_FUZZ_SOCK_PATH"),
        logLevel: getEnv("JAM_FUZZ_LOG_LEVEL"))
  var writes = 0'u64
  var writeBytes = 0'u64
  if not budget(arguments[3], 1000000, writes) or not budget(arguments[4], 67108864,
      writeBytes): return 2
  let loadedPolicy = readBoundedFile(arguments[1], ByteLimit(CurrentDownloadPolicyBytes))
  let loadedParameters = readBoundedFile(arguments[2], ByteLimit(8388608))
  if loadedPolicy.error != AtomicFileError.None or loadedParameters.error != AtomicFileError.None:
    stderr.writeLine("FUZZ_START_FAILED configuration files")
    return 2
  let policy = decodeCurrentDownloadPolicy(text(loadedPolicy.value))
  let parameters = configuredParameters(text(loadedParameters.value))
  if policy.error != CurrentDownloadPolicyError.None or not parameters.ok:
    stderr.writeLine("FUZZ_START_FAILED configuration encoding")
    return 2
  let prepared = prepareFuzzTarget(environment, parameters.value, policy.value.candidate,
      ElementLimit(writes), ByteLimit(writeBytes))
  if prepared.error != FuzzTargetError.None:
    stderr.writeLine("FUZZ_START_FAILED " & $prepared.error)
    return 2
  let config = prepared.value
  var directory = config.dataPath
  var status = default(FileStatus)
  if readStatus(directory.toCString(), status) != 0 or not S_ISDIR(Mode(status.st_mode)) or
      uint32(status.st_uid) != effectiveUid() or (uint32(status.st_mode) and 0o077'u32) != 0:
    stderr.writeLine("FUZZ_START_FAILED private data directory")
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
