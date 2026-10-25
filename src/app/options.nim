# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared application configuration, parsed once before any service opens a socket.
## Options owns copied positional arguments and explicit enable/configuration values. Failed parsing
## clears the output; private fields and read accessors prevent partial configuration from escaping.

import std/[strutils, assertions]
import ../codec/bounded

const
  MaxDownloadBlocks* = 64             ## A command requests a finite number of actual successive adoptions.
  MaxDownloadAncestors* = 64          ## Hard path-count cap before any ancestor file IO or native setup.
  DefaultCompactionBytes = 64'u64*1024*1024 # Managed maintenance is bounded independently of write policy.
  MaximumCompactionBytes = 128'u64*1024*1024 # Leave journal capacity for a bounded final publication frame.
  DefaultStateWrites = 1000'u64       # CLI defaults do not widen explicitly supplied component policies.
  DefaultStateWriteBytes = 100000'u64 # Each omitted mutation ceiling resolves independently.
  Switches = ["--with-ui", "--with-rpc", "--with-management", "--with-telemetry", "--with-state",
      "--download-local-ancestors", "--download-update-logical-source", "--state-paged-resume"]
  Values = ["--trace-observations", "--telemetry", "--chain", "--management-socket", "--rpc-port",
      "--ui-port", "--dev-ui-dir", "--state-writes", "--state-write-bytes", "--state-checkpoint",
      "--state-trust", "--state-header",
      "--state-checkpoint-bytes", "--state-storage", "--state-db", "--state-layout",
      "--state-migrate-from",
      "--state-compact-bytes", "--download-ancestor", "--download-blocks",
      "--download-remote-ancestors", "--download-discover-ancestors",
      "--download-logical-source", "--download-logical-policy", "--download-namespace-policy"]

type StateStorage* {.pure.} = enum ## Backend choice is independent of future full/light node modes.
  Memory, Disk

type StateDiskLayout* {.pure.} = enum ## Physical layout is independent of memory/disk and future full/light selection.
  Journal, Managed, Paged

type Options* = object ## Validated service controls; command handlers validate their positional shapes.
  parsed, telemetry, rpc, ui, state, recover, localAncestors, management, updateLogicalSource: bool
  positional: seq[string]
  ancestorFiles: seq[string]
  downloadCount, remoteAncestors, discoverAncestors: int
  endpoint, chain, directory, managementPath: string
  recoveryFile, recoveryIdentity, recoveryHeader: string
  logicalSource, logicalPolicy, namespacePolicy, observations: string
  backend: StateStorage
  layout: StateDiskLayout
  pagedResume: bool
  compactBytes: ByteLimit
  database, migrateFrom: string
  rpcNumber, uiNumber: uint16
  writeCount: ElementLimit
  writeBytes, recoveryBytes: ByteLimit

proc valid*(options: Options): bool =
  ## A failed/default configuration has no executable command or enabled services.
  options.parsed

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

proc managementSocket*(options: Options): string =
  ## Only explicit activation returns a pathname; configuring a path never starts management.
  if options.parsed and options.management: options.managementPath else: ""

proc uiPort*(options: Options): uint16 =
  ## An enabled UI listener uses the validated configured port, defaulting to 8888.
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
  if text.len == 0 or text.len > 5: return 0
  var port = 0
  for digit in text: # Five decimal digits bound every intermediate arithmetic operation.
    if digit notin {'0'..'9'}: return 0
    port = port * 10 + ord(digit) - ord('0')
  if port notin 1..65535: return 0
  uint16(port)

proc decimalLimit(text: string, value: var uint64): bool =
  ## Parse bounded unsigned decimal without wrapping; zero is valid and never doubles as a failure sentinel.
  value = 0
  if text.len == 0 or text.len > 20: return false
  for character in text:
    if character notin {'0'..'9'}: return false # Reject signs, whitespace and non-ASCII numerals.
    let digit = uint64(ord(character) - ord('0'))
    if value > (high(uint64) - digit) div 10: return false # Prove the next multiply/add before either can wrap.
    value = value * 10 + digit
  true

proc parseOptions*(arguments: seq[string], options: var Options): bool =
  ## Parse unique trailing controls atomically; repeated invocations own independent configuration.
  options = default(Options)
  var candidate = Options(rpcNumber: 19800, uiNumber: 8888, downloadCount: 1,
    writeCount: ElementLimit(DefaultStateWrites), writeBytes: ByteLimit(DefaultStateWriteBytes),
    compactBytes: ByteLimit(DefaultCompactionBytes))
  var first = arguments.len
  for i in 0..<arguments.len: # Only reserved service controls begin the trailing option region.
    if arguments[i] in Switches or arguments[i] in Values:
      first = i
      break
  for i in 0..<first: candidate.positional.add(arguments[i]) # Copy caller arguments into this owner.
  var seen: seq[string] = @[]
  var i = first
  while i < arguments.len: # Reject unknown, duplicate, missing and option-valued pairs before use.
    let name = arguments[i]
    if name in seen and name != "--download-ancestor": return false
    if name notin seen: seen.add(name) # Only ancestor paths form a bounded repeatable control.
    if name in Switches:
      case name
      of "--with-telemetry": candidate.telemetry = true
      of "--with-rpc": candidate.rpc = true
      of "--with-management": candidate.management = true
      of "--with-ui": candidate.ui = true
      of "--with-state": candidate.state = true
      of "--state-paged-resume": candidate.pagedResume = true
      of "--download-local-ancestors": candidate.localAncestors = true
      of "--download-update-logical-source": candidate.updateLogicalSource = true
      else: return false # Switch classification above makes this branch unreachable.
      inc i
    elif name in Values:
      if arguments.len - i < 2: return false
      let value = arguments[i + 1]
      if value.len == 0 or value.startsWith("--"): return false
      case name
      of "--telemetry": candidate.endpoint = value
      of "--chain": candidate.chain = value
      of "--management-socket":
        if value.len > 103 or value[0] != '/' or value.endsWith('/'): return false
        for character in value:
          if ord(character) < 32 or ord(character) ==
              127: return false # Native paths cannot truncate or carry controls.
        candidate.managementPath = value
      of "--dev-ui-dir": candidate.directory = value
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
      of "--download-blocks":
        var number = 0'u64
        if value[0] == '0' or not decimalLimit(value, number) or number == 0 or
            number > uint64(MaxDownloadBlocks): return false # Prove the positive native count before conversion.
        candidate.downloadCount = int(number)
      of "--download-remote-ancestors":
        var number = 0'u64
        if value[0] == '0' or not decimalLimit(value, number) or number == 0 or
            number > uint64(MaxDownloadAncestors):
          return false # One canonical positive decimal bounds remote request work before any IO.
        candidate.remoteAncestors = int(number)
      of "--download-discover-ancestors":
        var number = 0'u64
        if value[0] == '0' or not decimalLimit(value, number) or number == 0 or number > uint64(MaxDownloadAncestors):
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
        if not decimalLimit(value, number): return false # No partial or wrapped budget escapes the candidate.
        if name == "--state-writes": candidate.writeCount = ElementLimit(number)
        elif name == "--state-write-bytes": candidate.writeBytes = ByteLimit(number)
        elif name == "--state-compact-bytes":
          if number > MaximumCompactionBytes: return false
          candidate.compactBytes = ByteLimit(number)
        else: candidate.recoveryBytes = ByteLimit(number)
      of "--rpc-port", "--ui-port":
        let port = portValue(value)
        if port == 0: return false # Never narrow a malformed or overflowing port.
        if name == "--rpc-port": candidate.rpcNumber = port
        else: candidate.uiNumber = port
      else: return false # All value-taking controls have an explicit assignment above.
      i += 2
    else: return false # Trailing controls never become protocol fixture modes.
  let hasWrites = "--state-writes" in seen
  let hasBytes = "--state-write-bytes" in seen
  if candidate.state:
    if candidate.chain.len == 0: return false # Activation still requires an explicit selected chain; omitted budgets use defaults.
  elif hasWrites or hasBytes:
    return false # Unselected policy controls must not be silently ignored.
  let hasBackend = "--state-storage" in seen
  let hasDatabase = "--state-db" in seen
  if (hasBackend or hasDatabase) and not candidate.state:
    return false # Explicit backend controls must never be silently ignored.
  if candidate.backend == StateStorage.Disk:
    if not hasDatabase: return false # Every disk run selects its exact path before opening storage.
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
  if recoveryCount > 0:
    if candidate.migrateFrom.len > 0: return false # Imported external authority and local migration are separate startup intentions.
    if not candidate.state or recoveryCount != recoveryControls.len:
      return false # Partial/disabled external imports cannot activate or reuse an earlier successful parse.
    candidate.recover = true
  if candidate.management and candidate.managementPath.len == 0: return false # No default endpoint is invented.
  if candidate.telemetry and (candidate.endpoint.len == 0 or candidate.chain.len == 0): return false
  if candidate.chain.len > 0 and not (candidate.telemetry or candidate.rpc or
      candidate.ui or candidate.state): return false
  if candidate.ui and candidate.uiNumber == candidate.rpcNumber: return false
  let downloadCommand = candidate.positional.len > 0 and
    candidate.positional[0] in ["download", "download-current"] # Both explicit pipelines share only command-shape validation.
  if candidate.telemetry or candidate.rpc or candidate.ui or candidate.state or
      candidate.management:
    if candidate.positional.len == 0 or candidate.positional[0] notin ["server", "client", "mesh",
        "download", "download-current", "check-traces"]:
      return false # Explicit state/service activation belongs only to supported command shapes.
  let traceCommand = candidate.positional.len > 0 and candidate.positional[0] == "check-traces"
  if "--trace-observations" in seen and not traceCommand:
    return false # External observations belong only to explicit offline comparison, never another command's ignored controls.
  if traceCommand:
    if not candidate.state or candidate.positional.len < 4 or candidate.positional.len > 259:
      return false # One explicit policy, Genesis and1..256 consecutive steps define a finite offline workload.
    for control in seen:
      if control notin ["--with-state", "--chain", "--state-writes", "--state-write-bytes",
          "--trace-observations"]:
        return false # Offline validation accepts only its explicit trust/state budgets; no listener, disk, recovery or download control is silently ignored.
  if downloadCommand:
    if not candidate.state or candidate.telemetry: return false # Downloads require explicit canonical state; outgoing telemetry is not wired yet.
  if candidate.ancestorFiles.len > 0 or "--download-blocks" in seen or candidate.localAncestors or
      candidate.remoteAncestors > 0 or candidate.discoverAncestors > 0:
    if not downloadCommand or not candidate.state:
      return false # Other commands must not silently ignore supplied download controls.
  if candidate.remoteAncestors > 0 and candidate.discoverAncestors > 0:
    return false # Up-front fixed acquisition and child-driven discovery are explicit alternative command modes.
  if candidate.logicalSource.len > 0 or candidate.logicalPolicy.len > 0 or
      candidate.namespacePolicy.len > 0 or candidate.updateLogicalSource:
    if candidate.logicalSource.len == 0 or candidate.logicalPolicy.len == 0 or
        candidate.positional.len == 0 or candidate.positional[0] != "download-current" or
            not candidate.state:
      return false # Neither unpaired controls nor other commands can silently ignore a logical startup request.
  candidate.parsed = true
  options = candidate # Only a complete validated configuration replaces the cleared output.
  true
