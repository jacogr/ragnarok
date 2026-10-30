# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Offline bounded checking of published Genesis and consecutive TraceStep files against explicitly configured trust/profile/policies.
## Only a private ephemeral chain advances; configured files, persistent storage and listeners are never opened for mutation.
import ../options
import ../current/download/policy as current_download_policy
import ./bootstrap as trace_bootstrap
import "./import" as trace_import
import ../[chain, candidate]
import ../../chain/[parameters, genesis, provider]
import ../../codec/[bounded, header]
import ../../codec/state/trie as state_trie
import ../../state/trace/[genesis as trace_genesis, step as trace_step, state as trace_state,
    file as trace_file]
import ../../state/store
import ../../state/accumulation/current/update as accumulation_current_update
import ../../lib/atomic/file as atomic_file
from ../../rpc/protocol import configuredParameters, configuredGenesis

const
  TraceCheckConfigBytes = 8388608 ## Existing strict chainspec JSON transport cap is independent of every binary file's resource policy.
  TraceCheckFileBytes = 16777216 ## One finite complete Genesis/TraceStep file is read at a time.
type
  TraceCheckCommandError* {.pure.} = enum ## Process-level refusals describe validation progress and expose no installable update or canonical owner.
    Uninitialized, None, InvalidArguments, InvalidPolicy, FileFailure, InvalidChain,
      GenesisFailure, TrailingGenesis, BootstrapFailure, TraceFailure, ObservationFailure,
        ImportFailure,
      AncestorLimit, StateChanged
  TraceCheckCommandOutcome* = object ## Only complete success has a verified final root; failure diagnostics and scalar progress contain no chain authority.
    requested, checked: int
    diagnostic: string
    case status: TraceCheckCommandError
    of None: root: StateRoot
    else: discard # A failed/default command has no final successful root or prepared graph.

func error*(outcome: TraceCheckCommandOutcome): TraceCheckCommandError =
  ## Inspect the selected command completion stage.
  outcome.status

func requestedBlocks*(outcome: TraceCheckCommandOutcome): int =
  ## Requested finite work is metadata, not an accepted-input or execution receipt.
  outcome.requested

func checkedBlocks*(outcome: TraceCheckCommandOutcome): int =
  ## Count only complete actual STF/map agreement within this private offline run.
  outcome.checked

func detail*(outcome: TraceCheckCommandOutcome): string =
  ## Return only bounded locally generated typed-stage diagnostics, without raw input or file contents.
  outcome.diagnostic

func finalRoot*(outcome: TraceCheckCommandOutcome): StateRoot {.inline,
    requires: outcome.status == TraceCheckCommandError.None.} =
  ## A final root exists only after every requested trace was authentically executed and compared in full.
  outcome.root

func refused(reason: TraceCheckCommandError, requested, checked: int,
    detail = ""): TraceCheckCommandOutcome =
  ## Keep partial scalar diagnostics separate from any installable state or successful final root.
  TraceCheckCommandOutcome(status: reason, requested: requested, checked: checked,
      diagnostic: detail)

proc text(bytes: openArray[byte]): string =
  ## Copy one already bounded strict JSON input without converting or repairing payload bytes.
  result = newString(bytes.len)
  for index in 0..<bytes.len: result[index] = char(bytes[index])

proc observationPath(directory: string, ordinal: int): string =
  ## Option validation bounds the directory and1..256 file count proves the fixed four-digit nonnegative ordinal.
  const digits = "0123456789"
  result = directory & "/step-"
  for divisor in [1000, 100, 10, 1]: result.add(digits[(ordinal div divisor) mod 10])
  result.add(".bin")

proc runTraceChecks*(options: Options): TraceCheckCommandOutcome =
  ## Read explicit policy/configuration, anchor the supplied Genesis independently, then check consecutive signed files without changing an external chain or starting services.
  if not options.valid or not options.stateEnabled or options.argumentCount < 4 or
      options.argument(1) != "check-traces":
    return refused(TraceCheckCommandError.InvalidArguments, 0, 0)
  let requested = options.argumentCount-3
  let policyInput = readBoundedFile(options.argument(2), ByteLimit(CurrentDownloadPolicyBytes))
  if policyInput.error != AtomicFileError.None:
    return refused(TraceCheckCommandError.FileFailure, requested, 0, $policyInput.error)
  let policy = decodeCurrentDownloadPolicy(text(policyInput.value))
  if policy.error != CurrentDownloadPolicyError.None:
    return refused(TraceCheckCommandError.InvalidPolicy, requested, 0, $policy.error)
  var candidate = policy.value.candidate
  candidate.selectLogging(options.logWriter)
  candidate.selectPvmBackend(options.pvmBackend)
  let config = readBoundedFile(options.chainPath, ByteLimit(TraceCheckConfigBytes))
  if config.error != AtomicFileError.None:
    return refused(TraceCheckCommandError.FileFailure, requested, 0, $config.error)
  let encoded = text(config.value)
  let parameters = configuredParameters(encoded)
  if not parameters.ok:
    return refused(TraceCheckCommandError.InvalidChain, requested, 0, "Parameters")
  var statePolicy = genesisStoreLimits()
  statePolicy.writes = options.stateWrites
  statePolicy.writeValueBytes = options.stateWriteBytes
  let configured = configuredGenesis(encoded, parameters.value, statePolicy)
  if configured.error != GenesisError.None:
    return refused(TraceCheckCommandError.InvalidChain, requested, 0, $configured.error)
  let initial = readBoundedFile(options.argument(3), ByteLimit(TraceCheckFileBytes))
  if initial.error != AtomicFileError.None:
    return refused(TraceCheckCommandError.FileFailure, requested, 0, $initial.error)
  let bytes = initial.value
  let frame = candidate.reporting.admission.frame
  let decoded = decodeTraceGenesis(bytes, TraceGenesisLimits(header: HeaderConfig(
      cores: frame.cores, authorValidators: frame.validators, epochSlots: frame.epochSlots,
      maxBytes: candidate.headerBytes), state: statePolicy, bytes: ByteLimit(TraceCheckFileBytes)))
  if decoded.error != TraceGenesisError.None:
    return refused(TraceCheckCommandError.GenesisFailure, requested, 0, $decoded.error)
  if decoded.value.traceGenesisBytes.value != bytes.len:
    return refused(TraceCheckCommandError.TrailingGenesis, requested, 0)
  let trusted = configured.value
  let startup = bootstrapTraceChain(decoded.value, TraceBootstrapTrust(
      header: trusted.blockHash, state: trusted.stateSnapshot.commitment.root), parameters.value)
  if startup.error != TraceBootstrapError.None:
    return refused(TraceCheckCommandError.BootstrapFailure, requested, 0, $startup.error)
  var chain = startup.value
  var older: seq[OwnedHeader] = @[]
  var available = uint64(candidate.reporting.reports.ancestors.maxBytes)
  var checked = 0
  for index in 4..options.argumentCount:
    let before = chain.chainView.bestBlock.value
    let keep = index < options.argumentCount
    let extent = uint64(before.header.headerInfo.value.consumed)
    if keep and (uint64(older.len) >= uint64(candidate.reporting.reports.ancestors.headers) or
        extent > available):
      return refused(TraceCheckCommandError.AncestorLimit, requested,
          checked) # Reserve this exact retained header before preparing another private successor.
    let loaded = loadTraceStepFile(options.argument(index), TraceStepLimits(frame: frame,
        state: statePolicy, bytes: ByteLimit(TraceCheckFileBytes)))
    if loaded.error != TraceFileError.None:
      return refused(TraceCheckCommandError.TraceFailure, requested, checked, $loaded.error)
    var observation = default(TraceState)
    let directory = options.traceObservationsPath
    if directory.len != 0:
      let input = readBoundedFile(observationPath(directory, index-4), ByteLimit(TraceCheckFileBytes))
      if input.error != AtomicFileError.None:
        return refused(TraceCheckCommandError.ObservationFailure, requested, checked, $input.error)
      let bytes = input.value
      let decoded = decodeTraceState(bytes, statePolicy, ByteLimit(TraceCheckFileBytes))
      if decoded.error != TraceStateError.None:
        return refused(TraceCheckCommandError.ObservationFailure, requested, checked,
            $decoded.error)
      if decoded.value.traceStateInfo.value.consumed != bytes.len:
        return refused(TraceCheckCommandError.ObservationFailure, requested, checked, "TrailingBytes")
      observation = decoded.value # Only complete independently rooted regular-file EOF reaches actual external-map comparison.
    let prepared = if directory.len != 0:
        prepareTraceObservation(chain, loaded.value, observation, older, candidate)
      else: prepareTraceImport(chain, loaded.value, older,
          candidate) # Ordinary golden trace checking preserves its existing path.
    if prepared.error != TraceImportError.None:
      return refused(TraceCheckCommandError.ImportFailure, requested, checked, $prepared.error)
    if not chain.canInstallPrepared(prepared.value):
      return refused(TraceCheckCommandError.StateChanged, requested, checked)
    chain.installPrepared(prepared.value)
    inc checked # Only exact complete-map agreement followed by ordinary guarded private continuation counts as checked.
    if keep:
      available -= extent
      var next = @[before.header]
      for ancestor in older: next.add(ancestor) # The finite caller policy bounds every retained original ancestor and aggregate header byte.
      older = next
  TraceCheckCommandOutcome(status: TraceCheckCommandError.None, requested: requested,
      checked: checked, root: chain.stateSnapshot.value.commitment.root)
