# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete explicit CLI logical files drive actual authenticated adoption and disk restart; malformed syntax and incomplete identities grant no source prefix.
import std/[assertions, syncio, envvars, strutils, os]
import std/posix/posix
import ../../support/[current_logical_cli_context, current_namespace_policy_context,
    current_namespace_execution_context, current_application_context, current_consecutive_context,
    current_consecutive_download_context,
    current_services_disk_samples, managed_storage_samples, current_namespace_transition_context,
    current_download_command_context, block_download_transport]
import ../../../src/app/[current_logical_startup, current_logical_download, current_download_policy,
    current_download_command, options, services, chain]
import ../../../src/codec/[bounded, block_codec, report_owned, state_composition]
import ../../../src/chain/[provider, genesis]
import ../../../src/state/[store, parent_logical, accumulation_current_update, block_admission, report_admission]
import ../../../src/storage/managed_manifest
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Canonical lexical failures must perform no primitive work.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Native hash rejection makes accidental preflight hashing observable independently of return codes.
proc parser() =
  ## Strict declarations and every mandatory scalar leaf reject malformed/partial input without source access.
  let limits = logicalStartupTestLimits()
  let policy = encodeCurrentLogicalPolicy(limits)
  let good = decodeCurrentLogicalPolicy(policy)
  assert good.error == CurrentDownloadPolicyError.None
  assert encodeCurrentLogicalPolicy(good.value) == policy
  let rows = policy.splitLines()
  assert rows.len == 54, "logical header, 52 reviewed leaves and final LF"
  for missing in 1..<rows.high:
    var text = rows[0] & "\n"
    for i in 1..<rows.high:
      if i != missing: text.add(rows[i] & "\n")
    let refused = decodeCurrentLogicalPolicy(text)
    assert refused.error == CurrentDownloadPolicyError.MissingField
    assert refused.fieldName == rows[missing].substr(0, rows[missing].find('=')-1)
  for value in ["", "-1", "01", "18446744073709551616", " 1", "1 "]:
    let text = policy.replace("projection.services=" & $uint64(limits.projection.services),
        "projection.services=" & value)
    assert decodeCurrentLogicalPolicy(text).error == CurrentDownloadPolicyError.InvalidNumber
  assert decodeCurrentLogicalPolicy(policy & "projection.services=1\n").error ==
      CurrentDownloadPolicyError.DuplicateField
  assert decodeCurrentLogicalPolicy(policy & "unknown=1\n").error ==
      CurrentDownloadPolicyError.UnknownField
  let wide = decodeCurrentLogicalPolicy(policy.replace("projection.services=2",
      "projection.services=4294967296"))
  assert wide.error == CurrentDownloadPolicyError.None and uint64(wide.value.projection.services) == 4294967296'u64
  assert decodeCurrentLogicalPolicy("ragnarok-current-download-policy-v1\n").error ==
      CurrentDownloadPolicyError.WrongVersion
  let header = "ragnarok-current-logical-source-v1\n"
  failHash(1)
  for text in ["", "wrong\n", header & "s=042\n", header & "s=4294967296\n", header &
      "s=42\ns=42\n", header & "k=\n", header & "s=42\nk=Ff\n", header & "s=42\np=00\n", header &
      "s=42\nx=00\n",
      header & "s=42\nr=" & repeat('0', 64) & ":4294967294\n"]:
    assert decodeCurrentLogicalDeclarations(text, limits.projection).error !=
        CurrentLogicalStartupError.None
  assert decodeCurrentLogicalDeclarations(header & "s=42\nk=\n", limits.projection).error ==
      CurrentLogicalStartupError.None
  var small = limits.projection
  small.bytes = ByteLimit(0)
  assert decodeCurrentLogicalDeclarations(header, small).error ==
      CurrentLogicalStartupError.LimitExceeded
  small = limits.projection
  small.facts = ElementLimit(0)
  assert decodeCurrentLogicalDeclarations(header & "s=42\n", small).error ==
      CurrentLogicalStartupError.LimitExceeded
  assert hashCalls() == 0
  assert decodeCurrentLogicalDeclarations(header & "s=4294967295\nk=\nr=" & repeat('0', 64) &
      ":4294967293", limits.projection).error == CurrentLogicalStartupError.None
  assert decodeCurrentLogicalDeclarations(header & "s=42\nk=" & repeat('0', 8194),
      limits.projection).error == CurrentLogicalStartupError.LimitExceeded
  assert decodeCurrentLogicalDeclarations(header & repeat('#', CurrentLogicalSourceBytes),
      limits.projection).error == CurrentLogicalStartupError.LimitExceeded
  var many = limits.projection
  many.facts = ElementLimit(10000)
  many.bytes = ByteLimit(10000000)
  assert decodeCurrentLogicalDeclarations(header & "s=42\n" & repeat("k=\n", 4096), many).error ==
      CurrentLogicalStartupError.LimitExceeded
  failHash(0)
proc fileChecks() {.raises.} =
  ## File transport admits cap+1 only, rejects missing sources and shares the scalar policy reader without starting Services.
  var path = "pvm-logical-cli-file-boundary"
  discard posix.unlink(path.toCString())
  defer: discard posix.unlink(path.toCString())
  let limits = logicalStartupTestLimits()
  assert loadCurrentLogicalDeclarations(path, limits.projection).error ==
      CurrentLogicalStartupError.FileFailure
  assert loadCurrentLogicalPolicy(path).error == CurrentDownloadPolicyError.FileFailure
  writeFile(path, repeat('x', CurrentLogicalSourceBytes+1))
  assert loadCurrentLogicalDeclarations(path, limits.projection).error ==
      CurrentLogicalStartupError.LimitExceeded
  assert loadCurrentLogicalPolicy(path).error == CurrentDownloadPolicyError.LimitExceeded
  writeFile(path, "ragnarok-current-logical-source-v1\ns=42\nk=\n")
  assert loadCurrentLogicalDeclarations(path, limits.projection).error ==
      CurrentLogicalStartupError.None
  writeFile(path, encodeCurrentLogicalPolicy(limits))
  assert loadCurrentLogicalPolicy(path).error == CurrentDownloadPolicyError.None
proc joined(left, right: seq[string]): seq[string] =
  ## Pinned Nimony appends one explicit argument at a time; no sequence-concatenation API is assumed.
  result = left
  for value in right: result.add(value)
proc optionChecks() =
  ## Paired command-specific paths are atomic; failed reparsing cannot retain a previous enabled logical request.
  let base = @["download-current", "--with-state", "--chain", "chain.json"]
  let pair = @["--download-logical-source", "source.txt", "--download-logical-policy", "logical.txt"]
  var options = default(Options)
  assert parseOptions(joined(base, pair), options) and options.logicalDownloadEnabled
  assert options.logicalDownloadSourcePath == "source.txt" and options.logicalDownloadPolicyPath == "logical.txt"
  for extra in [@["--download-logical-source", "source.txt"], @["--download-logical-policy",
      "logical.txt"], joined(pair, @["--download-logical-source", "again"]), @[
          "--download-logical-source", "a\0b", "--download-logical-policy", "logical.txt"]]:
    assert not parseOptions(joined(base, extra), options)
    assert not options.valid and not options.logicalDownloadEnabled
    assert options.logicalDownloadSourcePath.len == 0 and options.logicalDownloadPolicyPath.len == 0
  for command in ["download", "server", "client", "mesh"]:
    assert not parseOptions(joined(@[command, "--with-state", "--chain", "chain.json"], pair), options)
  assert parseOptions(base, options) and not options.logicalDownloadEnabled
proc sourceChecks(fixture: NamespaceExecutionFixture) =
  ## Every declared payload comes from the actual complete source; omissions, duplicates, missing values and policy refusal retain exact failed stages.
  let services = fixture.executableNamespaceServices(fixture.parent.bestBlock.value.stateSnapshot)
  let text = logicalDeclarationText(services)
  let limits = logicalStartupTestLimits()
  let declarations = decodeCurrentLogicalDeclarations(text, limits.projection).value
  let captured = captureCurrentLogicalStartup(fixture.parent, declarations, limits)
  assert captured.error == CurrentLogicalStartupError.None
  var omitted = ""
  var skipped = false
  for row in text.splitLines():
    if not skipped and row.startsWith("p="): skipped = true
    else: omitted.add(row & "\n")
  let missing = decodeCurrentLogicalDeclarations(omitted, limits.projection).value
  let refused = captureCurrentLogicalStartup(fixture.parent, missing, limits)
  assert refused.error == CurrentLogicalStartupError.LogicalFailure
  assert refused.logicalFailure.error == ParentLogicalError.ManifestFailure
  let absent = decodeCurrentLogicalDeclarations(text & "k=ff\n", limits.projection).value
  assert captureCurrentLogicalStartup(fixture.parent, absent, limits).error ==
      CurrentLogicalStartupError.SourceFailure
  let duplicate = decodeCurrentLogicalDeclarations(text & "k=" & logicalHex(services[
      services.high].storage[0].key) & "\n", limits.projection).value
  assert captureCurrentLogicalStartup(fixture.parent, duplicate, limits).error ==
      CurrentLogicalStartupError.LogicalFailure
  var smaller = limits
  smaller.projection.bytes = ByteLimit(0)
  assert captureCurrentLogicalStartup(fixture.parent, declarations, smaller).error ==
      CurrentLogicalStartupError.LimitExceeded
  smaller = limits
  smaller.profile.blocks = ElementLimit(0)
  assert captureCurrentLogicalStartup(fixture.parent, declarations, smaller).error ==
      CurrentLogicalStartupError.ProfileFailure
  smaller = limits
  smaller.globals.totalBytes = ByteLimit(0)
  assert captureCurrentLogicalStartup(fixture.parent, declarations, smaller).error ==
      CurrentLogicalStartupError.GlobalsFailure
proc command(fixture: NamespaceExecutionFixture, layout: int, malformed = false, omitted = false,
    refuse = false, namespaces = false, refresh = false, partial = false,
        unwritable = false) {.raises.} =
  ## Actual command sockets, worker collection and adoption use explicit files; strict disk restart reconstructs a fresh physical logical owner.
  var chainPath = "pvm-logical-cli-chain"
  var policyPath = "pvm-logical-cli-policy"
  var sourcePath = "pvm-logical-cli-source"
  let actualSourcePath = sourcePath
  var sourceDescriptor = -1.cint
  var logicalPolicyPath = "pvm-logical-cli-limits"
  var database = "pvm-logical-cli-state-" & $layout
  var namespacePath = "pvm-logical-cli-namespace-policy"
  defer:
    if sourceDescriptor >= 0: discard posix.close(
        sourceDescriptor) # Parent descriptor outlives every forked responder and source publication attempt.
    for name in [chainPath, policyPath, actualSourcePath, logicalPolicyPath, namespacePath]:
      var path = name
      discard posix.unlink(path.toCString())
    if layout == 2 and not malformed: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString())
  writeFile(chainPath, fixture.parent.bestBlock.value.currentApplicationText)
  let policy = currentConsecutivePolicy()
  writeFile(policyPath, encodeCurrentDownloadPolicy(policy))
  var limits = logicalStartupTestLimits()
  if refuse: limits.download.identities.keys = ElementLimit(0)
  writeFile(logicalPolicyPath, encodeCurrentLogicalPolicy(limits))
  var text = logicalDeclarationText(fixture.executableNamespaceServices(
      fixture.parent.bestBlock.value.stateSnapshot))
  if malformed: text = "wrong\n"
  if omitted:
    var reduced = ""
    var skipped = false
    for row in text.splitLines():
      if not skipped and row.startsWith("p="): skipped = true
      else: reduced.add(row & "\n")
    text = reduced
  writeFile(sourcePath, text)
  if unwritable:
    var nativePath = actualSourcePath
    sourceDescriptor = posix.open(nativePath.toCString(), O_RDONLY)
    assert sourceDescriptor >= 0
    sourcePath = "/dev/fd/" & $sourceDescriptor # A real readable regular source has a kernel descriptor-directory parent where atomic sibling creation must fail, including under root.
  let first = fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var model = initApplicationChain(fixture.update.currentUpdateView).value
  var heads = @[fixture.parent.bestBlock.value, model.chainView.bestBlock.value]
  var children = @[first]
  for index in 0..<2:
    let child = currentEmptyChild(model.chainView.bestBlock.value)
    let update = phaseCurrentUpdate(model, child, [], currentConsecutiveLimits())
    model.installPrepared(update)
    children.add(child)
    heads.add(model.chainView.bestBlock.value)
  var extra: seq[string] = @[]
  if refresh: extra.add("--download-update-logical-source") # Only explicit opt-in may replace the previously qualified input file.
  if namespaces:
    var namespacePolicy = namespacePolicyTestLimits()
    if refuse: namespacePolicy.continuation.scratchBytes = ByteLimit(
        0) # Preserve a genuine local continuation refusal after real receipt without adoption.
    writeFile(namespacePath, if malformed: "wrong\n" else: encodeCurrentNamespacePolicy(namespacePolicy))
    extra.add("--download-namespace-policy")
    extra.add(namespacePath)
  if layout != 0:
    for argument in ["--state-storage", "disk", "--state-db", database]: extra.add(argument)
    if layout == 2:
      for arg in ["--state-layout", "managed", "--state-compact-bytes", "0"]: extra.add(arg)
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  for i in 0..<3:
    requests.add(currentExpectedRequest(array[32, byte](heads[i].blockHash)))
    responses.add(currentConsecutiveResponse(children[i]))
  if partial: responses[1] = @[0'u8, 0, 0, 0] # The second authenticated response is genuinely empty; one attempt must exhaust after the first adopted child.
  let firstCount = if unwritable: 1 elif malformed or omitted or refuse or partial or (
      namespaces and not refresh) or layout == 0: 3 else: 1
  let exchanged = logicalCommandExchange(chainPath, policyPath, sourcePath, logicalPolicyPath,
      requests, responses, firstCount, extra)
  if malformed or omitted:
    assert exchanged.outcome.error == (if malformed and
        namespaces: CurrentDownloadCommandResult.InvalidPolicy else: CurrentDownloadCommandResult.InvalidLogicalSource)
    assert exchanged.outcome.adoptedBlocks == 0 and exchanged.secondRequests == 0
  elif unwritable:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.LogicalSourcePublicationFailure
    assert exchanged.outcome.adoptedBlocks == 1 and exchanged.secondRequests == 1
    assert readFile(actualSourcePath) == text # Ordinary atomic publication refusal preserves the entire previous source file.
  elif partial:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.Exhausted
    assert exchanged.outcome.adoptedBlocks == 1 and exchanged.secondRequests == 2
  elif refuse:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.Exhausted
    assert exchanged.outcome.adoptedBlocks == 0 and exchanged.secondRequests == 1
  else:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.Adopted
    assert exchanged.outcome.adoptedBlocks == firstCount and exchanged.secondRequests == firstCount
  if refresh and not malformed and not omitted and not refuse and not unwritable:
    let updated = readFile(actualSourcePath)
    if namespaces:
      assert updated != text and "k=07\n" in updated # Exported raw identity comes only from the actual qualified adopted source.
    else: assert updated == text # Strict identity preservation exports the same canonical declarations after actual adoption.
  if malformed:
    assert not fileExists(database) and not dirExists(
        database) # Lexical refusal precedes Services or database startup.
  elif layout != 0:
    if not omitted and not refuse and not unwritable and (not namespaces or refresh):
      var nextRequests: seq[array[42, byte]] = @[]
      var nextResponses: seq[seq[byte]] = @[]
      for i in 1..<3:
        nextRequests.add(requests[i]); nextResponses.add(currentConsecutiveResponse(children[i]))
      let restarted = logicalCommandExchange(chainPath, policyPath, sourcePath, logicalPolicyPath,
          nextRequests, nextResponses, 2, extra)
      assert restarted.outcome.error == CurrentDownloadCommandResult.Adopted
      assert restarted.outcome.adoptedBlocks == 2 and restarted.secondRequests == 2
    var owner = default(Services)
    let options = currentDiskOptions(chainPath, database, layout == 2, 0)
    assert owner.start(options, "strict CLI logical final reopen")
    assert owner.chainView.retainedCount == (if omitted or refuse: 1 elif unwritable: 2 else: 4)
    for i in 0..<owner.chainView.retainedCount:
      equalCurrentDiskMap(owner.chainView.retainedBlockAt(RetainedBlockIndex(uint64(
          i))).value.stateSnapshot, heads[i].stateSnapshot)
    owner.close()
proc main() {.raises.} =
  ## Source preflight is independent of primitive availability; actual command witnesses then bind complete signed namespaces and durable histories.
  parser()
  fileChecks()
  optionChecks()
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = namespaceExecutionFixture(decodeOwnedReport(bytes, 2).value, namespaceHaltCode(),
      namespaceHaltCode())
  let mutated = namespaceExecutionFixture(decodeOwnedReport(bytes, 2).value, namespaceHaltCode(),
      namespaceStorageCode(@[9'u8, 8]))
  sourceChecks(fixture)
  for layout in 0..2:
    command(fixture, layout)
    command(fixture, layout, refresh = true)
    command(fixture, layout, true)
    command(fixture, layout, false, true)
    command(fixture, layout, false, false, true)
    command(mutated, layout, namespaces = true)
    command(mutated, layout, namespaces = true, refuse = true)
    command(mutated, layout, namespaces = true, malformed = true)
    command(mutated, layout, namespaces = true, refresh = true)
    command(mutated, layout, namespaces = true, refresh = true, partial = true)
    command(mutated, layout, namespaces = true, refresh = true, unwritable = true)
  echo "PVM current logical startup passed"
try: main()
except: quit(2) # Parser, source matching, command adoption and every native cleanup path are mandatory evidence.
