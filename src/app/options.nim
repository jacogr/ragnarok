# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared application configuration, parsed once before any service opens a socket.
## Options owns normalized command arguments and explicit enable/configuration values. Failed parsing
## clears the output; private fields and read accessors prevent partial configuration from escaping.

import ../lib/logging

import std/[strutils, assertions]
import ../codec/bounded
import ../storage/history/index as history_index

import ./cli/[catalog as cli_catalog, commands as cli_commands, defaults as cli_defaults]
export cli_defaults

type Options* = object ## Validated service controls; command handlers validate their positional shapes.
  parsed, telemetry, rpc, mcp, ui, state, recover, localAncestors, management,
    updateLogicalSource: bool
  positional: seq[string]
  ancestorFiles: seq[string]
  downloadCount, remoteAncestors, discoverAncestors: int
  syncSourceAge, syncReconnect: uint64
  logging: LogPolicy
  output: LogWriter
  endpoint, chain, directory, managementPath, dataPath: string
  recoveryFile, recoveryIdentity, recoveryHeader: string
  logicalSource, logicalPolicy, namespacePolicy, observations: string
  mode: NodeMode
  codePath, codeEntry: string
  codeGas, codeSteps: uint64
  pvmSelection: PvmBackend
  backend: StateStorage
  layout: StateDiskLayout
  historyExplicit: bool
  history: HistoryPolicy
  historyHash, historyOutput: string
  historyNumber: HistoryOrdinal
  pagedResume: bool
  compactBytes: ByteLimit
  database, migrateFrom: string
  rpcNumber, mcpNumber, uiNumber: uint16
  writeCount: ElementLimit
  writeBytes, recoveryBytes: ByteLimit

func retentionSpecified*(options: Options): bool =
  ## Only an explicit full-state startup request can override a persisted history policy.
  options.parsed and options.historyExplicit
func retentionPolicy*(options: Options): HistoryPolicy =
  ## Failed/default options grant no configured historical policy.
  if options.parsed: options.history else: default(HistoryPolicy)
func historicalHash*(options: Options): string =
  ## An empty hash means the validated offline query selected a local ordinal.
  if options.parsed: options.historyHash else: ""
func historicalOrdinal*(options: Options): HistoryOrdinal =
  ## Zero means no ordinal selector; successful offline queries always select exactly one addressing domain.
  if options.parsed: options.historyNumber else: HistoryOrdinal(0)
func historicalCheckpointPath*(options: Options): string =
  ## Only an explicit offline output path authorizes checkpoint publication.
  if options.parsed: options.historyOutput else: ""

proc valid*(options: Options): bool =
  ## A failed/default configuration has no executable command or enabled services.
  options.parsed

func pvmBackend*(options: Options): PvmBackend =
  ## Only the immutable parsed selection reaches invocation policy; failed parsing grants no startup authority.
  options.pvmSelection

func pvmCodePath*(options: Options): string =
  ## Only a complete standalone parse exposes an artifact filename.
  if options.parsed: options.codePath else: ""
func pvmEntry*(options: Options): string =
  ## The selected export is meaningful only for explicit standalone execution.
  if options.parsed: options.codeEntry else: ""
func pvmGas*(options: Options): uint64 =
  ## Finite validated gas never derives from an untrusted artifact declaration.
  if options.parsed: options.codeGas else: 0
func pvmSteps*(options: Options): uint64 =
  ## A separate instruction allowance bounds loops independently of gas.
  if options.parsed: options.codeSteps else: 0

func nodeMode*(options: Options): NodeMode =
  ## Mode observation grants no startup authority when parsing failed.
  options.mode
func lightMode*(options: Options): bool =
  ## Only successfully parsed explicit light activation selects partial-state ownership.
  options.parsed and options.mode == NodeMode.Light
func lightTrustPath*(options: Options): string {.requires: options.lightMode.} =
  ## Independent current identity is an operator input, never inferred from a native directory.
  options.recoveryIdentity
func lightHeaderPath*(options: Options): string {.requires: options.lightMode.} =
  ## Exact independently selected sealed-header bytes anchor light restart metadata.
  options.recoveryHeader

proc argumentCount*(options: Options): int =
  ## Count only positional command arguments, excluding all trailing service controls.
  options.positional.len

proc argument*(options: Options, index: Positive): string =
  ## Preserve one-based CLI positions without consulting process-global arguments again.
  assert options.parsed and index <= options.positional.len
  options.positional[index - 1]

proc ancestorPaths*(options: Options): seq[string] =
  ## Copy the explicit newest-first path list; failed/default options retain an empty list.
  result = newSeq[string](options.ancestorFiles.len)
  for index, path in options.ancestorFiles:
    result[index] = path # Callers cannot reorder or replace the parser's retained list.

func localDownloadAncestors*(options: Options): bool =
  ## Explicit download-only activation captures retained local parents; failed/default parsing never enables it.
  options.parsed and options.localAncestors

func remoteDownloadAncestors*(options: Options): int =
  ## Explicit finite descending context request; disabled/default/failed parses request no remote headers.
  if options.parsed: options.remoteAncestors else: 0

func discoverDownloadAncestors*(options: Options): int =
  ## Explicit whole-run on-demand header allowance; default/failed parses never enable acquisition.
  if options.parsed: options.discoverAncestors else: 0

func logicalDownloadEnabled*(options: Options): bool =
  ## Only a complete validated paired opt-in enables current logical CLI provisioning.
  options.parsed and options.logicalSource.len > 0
proc logicalDownloadSourcePath*(options: Options): string =
  ## Copy only the explicit parsed declaration path; failed/default options expose no partial source.
  if options.parsed: options.logicalSource else: ""
proc logicalDownloadPolicyPath*(options: Options): string =
  ## Complete separate resource-policy path is retained independently of the declaration file.
  if options.parsed: options.logicalPolicy else: ""

func updateLogicalDownloadSource*(options: Options): bool =
  ## Explicit paired opt-in updates only the already qualified source file after actual adoption and joined shutdown.
  options.parsed and options.updateLogicalSource

proc namespaceDownloadPolicyPath*(options: Options): string =
  ## Only an explicitly paired current logical download can expose this opt-in namespace resource path.
  if options.parsed: options.namespacePolicy else: ""

func downloadBlocks*(options: Options): int =
  ## Valid commands default to one child; failed/default parsing reports no requested work.
  if options.parsed: options.downloadCount else: 0

proc telemetryEnabled*(options: Options): bool =
  ## Endpoint configuration alone never enables the exporter.
  options.parsed and options.telemetry

func stateEnabled*(options: Options): bool =
  ## Explicit activation and a selected chain use resolved default or overridden mutation budgets.
  options.parsed and options.state

func traceObservationsPath*(options: Options): string =
  ## Only the explicit offline checker may receive a bounded observation directory; failed/default options expose no path.
  if options.parsed: options.observations else: ""

func diskStorage*(options: Options): bool =
  ## Only a validated explicit disk request enables durable backend startup.
  options.parsed and options.state and options.backend == StateStorage.Disk
func managedStorage*(options: Options): bool =
  ## Only an explicitly selected managed disk layout enables managed startup or automatic reclamation.
  options.diskStorage and options.layout == StateDiskLayout.Managed
func pagedStorage*(options: Options): bool =
  ## Explicit physical selection requires the disk backend; it never infers mode, migration or an existing directory schema.
  options.diskStorage and options.layout == StateDiskLayout.Paged
func resumePagedStorage*(options: Options): bool =
  ## Only explicit paged disk startup can replay an independently prepared genesis/import or future publication target.
  options.pagedStorage and options.pagedResume
func stateCompactionBytes*(options: Options): ByteLimit {.requires: options.managedStorage.} =
  ## Return the managed soft journal threshold; explicit zero disables automatic maintenance.
  options.compactBytes
func stateMigration*(options: Options): bool =
  ## Only an explicit valid managed migration request grants source-file startup intent.
  options.managedStorage and options.migrateFrom.len > 0
func stateMigrationSource*(options: Options): string {.requires: options.stateMigration.} =
  ## Return the explicitly selected legacy source path; destination remains the separately selected state database.
  options.migrateFrom
func stateDatabase*(options: Options): string {.requires: options.diskStorage.} =
  ## Return the explicitly selected database path; no implicit location or overwrite is invented.
  options.database

func stateWrites*(options: Options): ElementLimit {.requires: options.parsed and options.state.} =
  ## Extract the resolved write-count budget; explicit zero overrides the CLI default.
  options.writeCount

func stateWriteBytes*(options: Options): ByteLimit {.requires: options.parsed and options.state.} =
  ## Extract the independent write-value byte budget; zero permits no written value bytes.
  options.writeBytes

func recoveryEnabled*(options: Options): bool =
  ## Only a complete explicit external-checkpoint request selects recovery.
  options.parsed and options.recover
func recoveryPath*(options: Options): string {.requires: options.parsed and options.recover.} =
  ## The checkpoint being imported is distinct from independently supplied trust paths.
  options.recoveryFile
func recoveryTrustPath*(options: Options): string {.requires: options.parsed and options.recover.} =
  ## Select the operator's independent fixed identity file.
  options.recoveryIdentity
func recoveryHeaderPath*(options: Options): string {.requires: options.parsed and
    options.recover.} =
  ## Select exact independently trusted sealed-header bytes.
  options.recoveryHeader
func recoveryByteLimit*(options: Options): ByteLimit {.requires: options.parsed and
    options.recover.} =
  ## Preserve the full unsigned explicit checkpoint ceiling; zero is a valid refusal policy.
  options.recoveryBytes

proc rpcPort*(options: Options): uint16 =
  ## UI implies RPC; configuration alone leaves the listener disabled.
  if options.parsed and (options.rpc or options.ui): options.rpcNumber else: 0'u16

proc mcpPort*(options: Options): uint16 =
  ## Port configuration alone cannot enable the agent listener.
  if options.parsed and options.mcp: options.mcpNumber else: 0'u16

proc managementSocket*(options: Options): string =
  ## Only explicit activation returns a pathname; configuring a path never starts management.
  if options.parsed and options.management: options.managementPath else: ""

proc uiPort*(options: Options): uint16 =
  ## An enabled UI listener uses the validated configured port, defaulting to 8418.
  if options.parsed and options.ui: options.uiNumber else: 0'u16

proc telemetryEndpoint*(options: Options): string =
  ## Return the explicit collector address; no default collector is invented.
  options.endpoint

proc chainPath*(options: Options): string =
  ## Canonical state, RPC and telemetry share this one explicit startup source.
  options.chain

proc devUiDirectory*(options: Options): string =
  ## Empty selects embedded assets; an override replaces the entire asset source.
  options.directory

# Prove decimal width and range before narrowing a configured listener port.
proc portValue(text: string): uint16 =
  ## Validate the full unsigned decimal before narrowing a configured listener port.
  var value = 0'u64
  if text.len > 5 or not unsignedValue(text, value) or value < 1 or value > 65535: return 0
  uint16(value)

proc parseCanonicalOptions*(arguments: seq[string], options: var Options,
    diagnostic: var string): bool =
  ## Internal configuration boundary: command values are already normalized; validate shared controls atomically.
  options = default(Options)
  var candidate = Options(syncSourceAge: 30000, syncReconnect: 5000, dataPath: DefaultDataDirectory,
      codeEntry: "main", codeGas: 10000000, codeSteps: 10000000, logging: initLogPolicy(),
          rpcNumber: DefaultRpcPort, mcpNumber: DefaultMcpPort, uiNumber: DefaultUiPort,
              downloadCount: DefaultDownloadBlocks, mode: DefaultNodeMode,
                  backend: DefaultStateStorage, pvmSelection: DefaultPvmBackend,
      layout: DefaultStateLayout,
    writeCount: ElementLimit(DefaultStateWrites), writeBytes: ByteLimit(DefaultStateWriteBytes),
    compactBytes: ByteLimit(DefaultCompactionBytes))
  candidate.history = boundedHistoryPolicy(DefaultRetainedBlocks).value
  var first = arguments.len
  for i in 0..<arguments.len: # Only reserved service controls begin the trailing option region.
    if optionIndex(arguments[i]) >= 0:
      first = i
      break
  for i in 0..<first: candidate.positional.add(arguments[i]) # Copy caller arguments into this owner.
  var seen: seq[string] = @[]
  var i = first
  while i < arguments.len: # Reject unknown, duplicate, missing and option-valued pairs before use.
    let found = optionIndex(arguments[i])
    if found < 0:
      diagnostic = "Unknown option: " & arguments[i]
      return false
    let spec = OptionSpecs[found]
    let name = spec.name
    if name in seen and not spec.repeatable:
      diagnostic = "Option may be supplied only once: " & name
      return false
    if name notin seen: seen.add(name) # Only ancestor paths form a bounded repeatable control.
    if spec.value.len == 0:
      case name
      of "--with-telemetry": candidate.telemetry = true
      of "--with-rpc": candidate.rpc = true
      of "--with-mcp": candidate.mcp = true
      of "--with-management": candidate.management = true
      of "--with-ui": candidate.ui = true
      of "--with-state": candidate.state = true
      of "--archive":
        if candidate.historyExplicit:
          diagnostic = "Choose either --archive or --retain-blocks, once"
          return false # Alternate spellings cannot silently override an earlier selection.
        candidate.historyExplicit = true
        candidate.history = archiveHistoryPolicy()
      of "--state-paged-resume": candidate.pagedResume = true
      of "--download-local-ancestors": candidate.localAncestors = true
      of "--download-update-logical-source": candidate.updateLogicalSource = true
      else: return false # Switch classification above makes this branch unreachable.
      inc i
    else:
      if arguments.len - i < 2:
        diagnostic = "Missing " & spec.value & " after " & name
        return false
      let value = arguments[i + 1]
      if value.len == 0 or value.startsWith("--"):
        diagnostic = "Missing " & spec.value & " after " & name
        return false
      diagnostic = "Invalid value for " & name & ": " & spec.description
      case name
      of "--pvm-code", "--pvm-entry":
        if value.len > 4096: return false
        for character in value:
          if ord(character) < 32 or ord(character) ==
              127: return false # Preserve exact native paths and bounded terminal diagnostics.
        if name == "--pvm-code": candidate.codePath = value
        else: candidate.codeEntry = value
      of "--pvm-gas", "--pvm-steps":
        var amount = 0'u64
        if not unsignedValue(value, amount) or amount == 0: return false
        if name == "--pvm-gas":
          if amount > 1000000000000'u64: return false
          candidate.codeGas = amount
        else:
          if amount > 1000000000'u64: return false
          candidate.codeSteps = amount
      of "--retain-blocks":
        if candidate.historyExplicit:
          diagnostic = "Choose either --archive or --retain-blocks, once"
          return false
        candidate.historyExplicit = true
        if value == "-1": candidate.history = archiveHistoryPolicy()
        else:
          var number = 0'u64
          if not unsignedValue(value, number) or number == 0: return false
          candidate.history = boundedHistoryPolicy(number).value
      of "--history-block":
        if value.len != 64: return false
        for character in value:
          if character notin {'0'..'9', 'a'..'f'}: return false # One exact hash spelling is admitted before any database IO.
        candidate.historyHash = value
      of "--history-ordinal":
        var number = 0'u64
        if not unsignedValue(value, number) or number == 0: return false
        candidate.historyNumber = HistoryOrdinal(number)
      of "--history-checkpoint":
        if value.len > 4096: return false
        for character in value:
          if ord(character) < 32 or ord(character) == 127: return false
        candidate.historyOutput = value
      of "--log-level":
        if not parseLogPolicy(value, candidate.logging): return false
      of "--telemetry-endpoint": candidate.endpoint = value
      of "--data-dir":
        if value.find(char(0)) >= 0: return false
        candidate.dataPath = value
      of "--chain": candidate.chain = value
      of "--management-socket":
        if value.len > 103 or value[0] != '/' or value.endsWith('/'): return false
        for character in value:
          if ord(character) < 32 or ord(character) ==
              127: return false # Native paths cannot truncate or carry controls.
        candidate.managementPath = value
      of "--ui-dev-dir": candidate.directory = value
      of "--pvm-backend":
        if not parsePvmBackend(value, candidate.pvmSelection):
          diagnostic = "Invalid --pvm-backend: use jit|compiled|interpreted|polkavm-interpreted|polkavm-compiled"
          return false
      of "--state-checkpoint": candidate.recoveryFile = value
      of "--state-trust": candidate.recoveryIdentity = value
      of "--state-header": candidate.recoveryHeader = value
      of "--state-migrate-from":
        for character in value:
          if character == char(0): return false # Native path truncation cannot select a different source identity.
        candidate.migrateFrom = value
      of "--trace-observations":
        if value.len > 4096: return false
        for character in value:
          if ord(character) < 32 or ord(character) ==
              127: return false # Keep the later fixed filename addition bounded and native path identity exact.
        candidate.observations = value
      of "--state-mode":
        case value
        of "full": candidate.mode = NodeMode.Full
        of "light": candidate.mode = NodeMode.Light
        else: return false # Mode is explicit and cannot be inferred from backend files.
      of "--state-layout":
        case value
        of "journal": candidate.layout = StateDiskLayout.Journal
        of "managed": candidate.layout = StateDiskLayout.Managed
        of "paged": candidate.layout = StateDiskLayout.Paged
        else: return false # Layout spelling is explicit; existing paths never select migration implicitly.
      of "--state-db": candidate.database = value
      of "--download-logical-source", "--download-logical-policy", "--download-namespace-policy":
        for character in value:
          if ord(character) < 32 or ord(character) ==
              127: return false # Native startup paths cannot be truncated or contain control bytes.
        if name == "--download-logical-source": candidate.logicalSource = value
        elif name == "--download-logical-policy": candidate.logicalPolicy = value
        else: candidate.namespacePolicy = value
      of "--sync-source-age-ms", "--sync-reconnect-ms":
        var number = 0'u64
        if not unsignedValue(value, number) or number == 0 or number > 3600000:
          return false # Bound independent host freshness/reconnect policy before any IO.
        if name == "--sync-source-age-ms": candidate.syncSourceAge = number
        else: candidate.syncReconnect = number
      of "--download-blocks":
        var number = 0'u64
        if value[0] == '0' or not unsignedValue(value, number) or number == 0 or
            number > uint64(MaxDownloadBlocks): return false # Prove the positive native count before conversion.
        candidate.downloadCount = int(number)
      of "--download-remote-ancestors":
        var number = 0'u64
        if value[0] == '0' or not unsignedValue(value, number) or number == 0 or
            number > uint64(MaxDownloadAncestors):
          return false # One canonical positive decimal bounds remote request work before any IO.
        candidate.remoteAncestors = int(number)
      of "--download-discover-ancestors":
        var number = 0'u64
        if value[0] == '0' or not unsignedValue(value, number) or number == 0 or number > uint64(MaxDownloadAncestors):
          return false # Whole-run header allowance is canonical, positive and finite before any command IO.
        candidate.discoverAncestors = int(number)
      of "--download-ancestor":
        if candidate.ancestorFiles.len == MaxDownloadAncestors or value in candidate.ancestorFiles:
          return false # Repeated paths cannot multiply IO/work or exceed the startup path ceiling.
        for character in value:
          if character == char(0): return false # Native path truncation must not change a selected header.
        candidate.ancestorFiles.add(value)
      of "--state-storage":
        case value
        of "memory": candidate.backend = StateStorage.Memory
        of "disk": candidate.backend = StateStorage.Disk
        else: return false # Backend spelling has one exact representation; light is not a backend.
      of "--state-writes", "--state-write-bytes", "--state-checkpoint-bytes", "--state-compact-bytes":
        var number = 0'u64
        if not unsignedValue(value, number): return false # No partial or wrapped budget escapes the candidate.
        if name == "--state-writes": candidate.writeCount = ElementLimit(number)
        elif name == "--state-write-bytes": candidate.writeBytes = ByteLimit(number)
        elif name == "--state-compact-bytes":
          if number > MaximumCompactionBytes: return false
          candidate.compactBytes = ByteLimit(number)
        else: candidate.recoveryBytes = ByteLimit(number)
      of "--rpc-port", "--ui-port", "--mcp-port":
        let port = portValue(value)
        if port == 0: return false # Never narrow a malformed or overflowing port.
        if name == "--rpc-port": candidate.rpcNumber = port
        elif name == "--mcp-port": candidate.mcpNumber = port
        else: candidate.uiNumber = port
      else: return false # All value-taking controls have an explicit assignment above.
      i += 2
  diagnostic = "Invalid option combination; see ragnarok " & (if candidate.positional.len >
      0: candidate.positional[0] else: "") & " --help"
  if candidate.historyExplicit and (not candidate.state or candidate.mode == NodeMode.Light):
    diagnostic = "Historical retention requires --with-state in full mode"
    return false # Partial state never acquires a complete historical-state contract.
  let hasWrites = "--state-writes" in seen
  let hasBytes = "--state-write-bytes" in seen
  if candidate.state:
    if candidate.chain.len == 0:
      diagnostic = "--with-state requires --chain FILE"
      return false # Activation still requires an explicit selected chain; omitted budgets use defaults.
  elif hasWrites or hasBytes:
    return false # Unselected policy controls must not be silently ignored.
  let hasBackend = "--state-storage" in seen
  let hasDatabase = "--state-db" in seen
  if (hasBackend or hasDatabase) and not candidate.state:
    return false # Explicit backend controls must never be silently ignored.
  if candidate.backend == StateStorage.Disk:
    if not hasDatabase:
      diagnostic = "--state-storage disk requires --state-db PATH"
      return false # Every disk run selects its exact path before opening storage.
  elif hasDatabase:
    return false # A memory run cannot silently ignore a requested physical database.
  if "--state-layout" in seen and candidate.backend != StateStorage.Disk: return false
  if candidate.pagedResume and not (candidate.state and candidate.backend == StateStorage.Disk and
      candidate.layout == StateDiskLayout.Paged):
    return false # Explicit replay is never accepted for memory, journal, managed or disabled-state operation.
  if "--state-compact-bytes" in seen and not (candidate.backend == StateStorage.Disk and
      candidate.layout == StateDiskLayout.Managed): return false # Never silently ignore maintenance controls.
  if "--state-migrate-from" in seen:
    if candidate.backend != StateStorage.Disk or candidate.layout != StateDiskLayout.Managed or
        candidate.migrateFrom == candidate.database:
      return false # Local migration is explicit, managed-only and never an in-place conversion.
  let recoveryControls = ["--state-checkpoint", "--state-trust", "--state-header", "--state-checkpoint-bytes"]
  var recoveryCount = 0
  for control in recoveryControls:
    if control in seen: inc recoveryCount # Seen uniqueness bounds this count to the fixed four controls.
  if candidate.mode == NodeMode.Light:
    # Partial mode has independent current trust and never accepts complete-state recovery/migration or execution-only controls.
    if not candidate.state or candidate.chain.len == 0 or recoveryCount != 2 or
        candidate.recoveryIdentity.len == 0 or candidate.recoveryHeader.len == 0:
      return false # A light owner cannot start with missing/partial current authority.
    if "--state-checkpoint" in seen or "--state-checkpoint-bytes" in seen or
        hasWrites or hasBytes or candidate.pagedResume or candidate.migrateFrom.len > 0:
      return false # No complete map, unsupported implicit replay or ignored mutation policy enters light startup.
    if candidate.backend == StateStorage.Disk and candidate.layout != StateDiskLayout.Paged:
      return false # Journal/managed schemas do not represent the light proof database.
    if candidate.positional.len > 0 and candidate.positional[0] in ["download", "download-current",
        "sync-current"]:
      return false # Complete execution/download commands cannot masquerade as partial light operation.
    for path in [candidate.recoveryIdentity, candidate.recoveryHeader]:
      for character in path:
        if ord(character) < 32 or ord(character) ==
            127: return false # Native trust paths cannot truncate or carry controls.
  elif recoveryCount > 0:
    if candidate.migrateFrom.len > 0: return false # Imported external authority and local migration are separate startup intentions.
    if not candidate.state or recoveryCount != recoveryControls.len:
      return false # Partial/disabled external imports cannot activate or reuse an earlier successful parse.
    candidate.recover = true
  if candidate.management and candidate.managementPath.len == 0:
    diagnostic = "--with-management requires --management-socket PATH"
    return false # No default endpoint is invented.
  if candidate.telemetry and (candidate.endpoint.len == 0 or candidate.chain.len == 0):
    diagnostic = "--with-telemetry requires --telemetry-endpoint HOST:PORT and --chain FILE"
    return false
  if candidate.chain.len > 0 and not (candidate.telemetry or candidate.rpc or
      candidate.ui or candidate.state or candidate.mcp): return false
  if candidate.ui and candidate.uiNumber == candidate.rpcNumber:
    diagnostic = "--ui-port and --rpc-port must differ when --with-ui is enabled"
    return false
  if candidate.mcp:
    if ((candidate.rpc or candidate.ui) and candidate.mcpNumber == candidate.rpcNumber) or
        (candidate.ui and candidate.mcpNumber == candidate.uiNumber):
      diagnostic = "--mcp-port must differ from enabled RPC/UI ports"
      return false
  let downloadCommand = candidate.positional.len > 0 and
    candidate.positional[0] in ["download", "download-current",
        "sync-current"] # Both explicit pipelines share only command-shape validation.
  if candidate.telemetry or candidate.rpc or candidate.ui or candidate.state or
      candidate.management or candidate.mcp:
    if candidate.positional.len == 0 or candidate.positional[0] notin ["server", "client", "mesh",
        "download", "download-current", "sync-current", "check-traces", "history"]:
      return false # Explicit state/service activation belongs only to supported command shapes.
  let historyCommand = candidate.positional.len == 1 and candidate.positional[0] == "history"
  let historyControls = candidate.historyHash.len > 0 or uint64(candidate.historyNumber) > 0 or
      candidate.historyOutput.len > 0
  if historyCommand:
    if not candidate.state or candidate.mode != NodeMode.Full or candidate.backend !=
        StateStorage.Disk:
      return false # The offline command queries an existing complete-state database under its exclusive lease.
    if (candidate.historyHash.len > 0) == (uint64(candidate.historyNumber) > 0): return false
    if candidate.historyOutput.len > 0 and candidate.historyOutput ==
        candidate.database: return false
    for control in seen:
      if control notin ["--log-level", "--chain", "--with-state", "--state-storage", "--state-db",
          "--state-layout", "--state-writes", "--state-write-bytes", "--history-block",
          "--history-ordinal", "--history-checkpoint"]:
        return false # Queries cannot start listeners, import/create authority, migrate or change retention.
  elif historyControls:
    return false # Query selectors/output never become ignored controls on another command.
  let traceCommand = candidate.positional.len > 0 and candidate.positional[0] == "check-traces"
  if "--trace-observations" in seen and not traceCommand:
    return false # External observations belong only to explicit offline comparison, never another command's ignored controls.
  if traceCommand:
    if not candidate.state or candidate.positional.len < 4 or candidate.positional.len >
        3+MaxTraceSteps:
      return false # One explicit policy, Genesis and1..256 consecutive steps define a finite offline workload.
    for control in seen:
      if control notin ["--log-level", "--pvm-backend", "--with-state", "--chain", "--state-writes",
          "--state-write-bytes", "--trace-observations"]:
        return false # Offline validation accepts only its explicit trust/state budgets; no listener, disk, recovery or download control is silently ignored.
  if downloadCommand:
    if not candidate.state or candidate.telemetry: return false # Downloads require explicit canonical state; outgoing telemetry is not wired yet.
  if candidate.ancestorFiles.len > 0 or "--download-blocks" in seen or candidate.localAncestors or
      candidate.remoteAncestors > 0 or candidate.discoverAncestors > 0:
    if not downloadCommand or not candidate.state:
      return false # Other commands must not silently ignore supplied download controls.
  let syncing = candidate.positional.len > 0 and candidate.positional[0] == "sync-current"
  if syncing and ("--download-blocks" in seen or candidate.updateLogicalSource):
    return false # A continuous host has no finite total; logical file export remains a joined finite command operation.
  if not syncing and ("--sync-source-age-ms" in seen or "--sync-reconnect-ms" in seen):
    return false # Unrelated lifecycles cannot silently ignore sync resource controls.
  if candidate.remoteAncestors > 0 and candidate.discoverAncestors > 0:
    return false # Up-front fixed acquisition and child-driven discovery are explicit alternative command modes.
  if candidate.logicalSource.len > 0 or candidate.logicalPolicy.len > 0 or
      candidate.namespacePolicy.len > 0 or candidate.updateLogicalSource:
    let currentCommand = candidate.positional.len > 0 and
      candidate.positional[0] in ["download-current", "sync-current"]
    if candidate.logicalSource.len == 0 or candidate.logicalPolicy.len == 0 or
        not currentCommand or not candidate.state:
      return false # Neither unpaired controls nor other commands can silently ignore a logical startup request.
  if candidate.codePath.len > 0:
    if candidate.positional.len != 0:
      diagnostic = "--pvm-code cannot accompany another command"
      return false
    for control in seen:
      if control notin ["--pvm-code", "--pvm-entry", "--pvm-gas", "--pvm-steps", "--pvm-backend",
          "--log-level"]:
        diagnostic = "Standalone PVM execution does not accept " & control
        return false # No service configuration is silently ignored.
  elif "--pvm-entry" in seen or "--pvm-gas" in seen or "--pvm-steps" in seen:
    diagnostic = "Standalone PVM options require --pvm-code FILE"
    return false
  candidate.parsed = true
  options = candidate # Only a complete validated configuration replaces the cleared output.
  true

func loggingPolicy*(options: Options): LogPolicy =
  ## Validated filters are configuration, not a mutable process global.
  options.logging
func logWriter*(options: Options): LogWriter =
  ## The application logger outlives the services and worker leases borrowing this handle.
  options.output
proc attachLogWriter*(options: var Options, writer: LogWriter) {.requires: options.parsed.} =
  ## Only validated options receive an explicitly started application-owned sink.
  options.output = writer
proc extractLoggingOptions*(arguments: seq[string], remaining: var seq[string],
    policy: var LogPolicy): bool =
  ## Dedicated command grammars consume the same unique logging option before their own parsing.
  remaining = @[]
  policy = initLogPolicy()
  var seen = false
  var index = 0
  while index < arguments.len:
    if arguments[index] == "--log-level":
      if seen or arguments.len-index < 2: return false
      if not parseLogPolicy(arguments[index+1], policy): return false
      seen = true
      index+=2
    else:
      remaining.add(arguments[index])
      inc index
  true

proc parseOptions*(arguments: seq[string], options: var Options, diagnostic: var string): bool =
  ## Normalize named commands, then commit only fully validated service configuration.
  options = default(Options)
  var normalized: seq[string] = @[]
  if not normalizeCommand(arguments, normalized, diagnostic): return false
  if not parseCanonicalOptions(normalized, options, diagnostic): return false
  if normalized.len > 0 and options.argumentCount == 0 and options.pvmCodePath.len == 0:
    options = default(Options)
    diagnostic = "Standalone PVM options require --pvm-code FILE"
    return false # Internal canonical parsing can describe backend-only harnesses; process input must select a workload.
  diagnostic = ""
  true

proc parseOptions*(arguments: seq[string], options: var Options): bool =
  ## Preserve existing pure callers while the application presents the diagnostic overload's actionable refusal.
  var diagnostic = ""
  parseOptions(arguments, options, diagnostic)

proc parseCanonicalOptions*(arguments: seq[string], options: var Options): bool =
  ## Component fixtures and internal adapters may supply normalized command values without pretending to parse process input.
  var diagnostic = ""
  parseCanonicalOptions(arguments, options, diagnostic)

proc dataDirectory*(options: Options): string =
  ## Persistent defaults are resolved once from the caller's selected root.
  if options.parsed: options.dataPath else: ""

func syncSourceAgeMs*(options: Options): uint64 =
  ## A validated continuous host alone consumes the independently configured freshness ceiling.
  if options.parsed: options.syncSourceAge else: 0
func syncReconnectMs*(options: Options): uint64 =
  ## Connection replacement has its own finite delay, independent of import or freshness deadlines.
  if options.parsed: options.syncReconnect else: 0
