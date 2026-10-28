# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete explicit CLI logical files drive actual authenticated adoption and disk restart; malformed syntax and incomplete identities grant no source prefix.
import std/[assertions, syncio, envvars, strutils, os]
import std/posix/posix
import ../../support/[current_logical_cli_context, current_namespace_policy_context,
    current_namespace_execution_context, current_service_replacement_context,
    current_application_context, current_consecutive_context,
    current_consecutive_download_context,
    current_services_disk_samples, managed_storage_samples, current_namespace_transition_context,
    current_download_command_context, block_download_transport]
import ../../support/pvm_accumulation_program
import ../../../src/pvm/machine
import ../../../src/app/[current_logical_startup, current_logical_download, current_download_policy,
    current_download_command, options, services, chain]
import ../../../src/codec/[bounded, block_codec, report_owned, state_composition, state_accounts,
    composite, state_service_values]
import ../../../src/chain/[provider, genesis]
import ../../support/accumulation_current_candidate_context
import ../../../src/state/service_identity_history
import ../../../src/state/[accumulation_effects, store, parent_logical, accumulation_current_update,
    block_admission, report_admission]
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
  assert parseCanonicalOptions(joined(base, pair), options) and options.logicalDownloadEnabled
  assert options.logicalDownloadSourcePath == "source.txt" and options.logicalDownloadPolicyPath == "logical.txt"
  for extra in [@["--download-logical-source", "source.txt"], @["--download-logical-policy",
      "logical.txt"], joined(pair, @["--download-logical-source", "again"]), @[
          "--download-logical-source", "a\0b", "--download-logical-policy", "logical.txt"]]:
    assert not parseCanonicalOptions(joined(base, extra), options)
    assert not options.valid and not options.logicalDownloadEnabled
    assert options.logicalDownloadSourcePath.len == 0 and options.logicalDownloadPolicyPath.len == 0
  for command in ["download", "server", "client", "mesh"]:
    assert not parseCanonicalOptions(joined(@[command, "--with-state", "--chain", "chain.json"],
        pair), options)
  assert parseCanonicalOptions(base, options) and not options.logicalDownloadEnabled
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
        unwritable = false, keyBytes = 0, replacement = false, omitMembership = false,
            sequential = false, retired = false, unsupported = false,
        replacementLength = 1, replacementHash = default(array[32, byte]),
            postBirth = false) {.raises.} =
  ## Actual command sockets, worker collection and adoption use explicit files; strict disk restart reconstructs a fresh physical logical owner.
  let refused = refuse or omitMembership or unsupported
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
  var policy = currentConsecutivePolicy()
  if keyBytes > 0:
    policy.candidate.completion.execution.initial.guests.copyBytes = MemoryByteLimit(8192)
    policy.candidate.completion.execution.execution.round.guests.copyBytes = MemoryByteLimit(
        8192) # Read the actual long zero-filled writable/heap span under explicit original policies.
  if sequential: policy.candidate.round.blockGas = Gas(
      200000) # Same original affordable-prefix policy as the signed fixture.
  if retired:
    # Original cleanup touches metadata, two storage keys, three requests and three preimages before retirement.
    policy.candidate.completion.execution.initial.guests.accountWriteFacts = ElementLimit(16)
    policy.candidate.completion.execution.initial.accounts.writes.writes = ElementLimit(16)
  if postBirth:
    # Actual same-invocation provide is independently bounded in guest retention and selected provision publication.
    policy.candidate.completion.execution.execution.round.guests.provisions = AccumulationProvisionLimits(
      items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
    policy.candidate.completion.execution.execution.round.provisions.values = PreimageLimits(
      items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
    policy.candidate.completion.execution.execution.round.provisions.encodedBytes = ByteLimit(128)
    policy.candidate.completion.execution.initial.guests.provisions = AccumulationProvisionLimits(
      items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
    policy.candidate.completion.execution.initial.provisions.values = PreimageLimits(
      items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
    policy.candidate.completion.execution.initial.provisions.encodedBytes = ByteLimit(128)
  if replacement:
    # Host capacities and selected history limits are separate original execution policies.
    policy.candidate.completion.execution.initial.guests.createdAccounts = ElementLimit(4)
    policy.candidate.completion.execution.initial.guests.deletedAccounts = ElementLimit(4)
    policy.candidate.completion.execution.execution.round.guests.createdAccounts = ElementLimit(4)
    policy.candidate.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(4)
  writeFile(policyPath, encodeCurrentDownloadPolicy(policy))
  var limits = logicalStartupTestLimits()
  if keyBytes > 0:
    limits.logical.inventory.manifest.storageKeyBytes = ByteLimit(8192)
    limits.logical.rawKeyBytes = ByteLimit(8192) # The actual logical state is valid independently of the narrower v1 source syntax.
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
    let parent = model.chainView.bestBlock.value
    let child = if retired: currentSameEpochBodyChild(parent, [0'u8, 0, 0, 0, 0, 0, 0])
      else: currentEmptyChild(parent) # Later-epoch expiry fixtures use the existing explicitly bounded signer.
    let update = phaseCurrentUpdate(model, child, [], policy.candidate)
    model.installPrepared(update)
    children.add(child)
    heads.add(model.chainView.bestBlock.value)
  var extra: seq[string] = @[]
  if refresh: extra.add("--download-update-logical-source") # Only explicit opt-in may replace the previously qualified input file.
  if namespaces:
    var namespacePolicy = namespacePolicyTestLimits()
    if replacement and not omitMembership:
      namespacePolicy.services = ServiceIdentityHistoryLimits(entries: ElementLimit(8),
        outcomes: ElementLimit(16), creations: ElementLimit(16), deletions: ElementLimit(16),
        bytes: ByteLimit(65536)) # Selected evidence remains distinct from enabled host capture.

    if keyBytes > 0:
      namespacePolicy.initial.storage.perKey = ByteLimit(8192)
      namespacePolicy.initial.storage.totalKeyBytes = ByteLimit(8192)
      namespacePolicy.round = namespacePolicy.initial
      namespacePolicy.continuation.logical.inventory.manifest.storageKeyBytes = ByteLimit(8192)
      namespacePolicy.continuation.logical.rawKeyBytes = ByteLimit(
          8192) # Genuine oversized identities reach completed logical qualification before export refuses them.
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
  let firstCount = if unwritable or keyBytes > CurrentLogicalSourceKeyBytes: 1 elif malformed or
      omitted or refused or partial or (namespaces and not refresh) or layout == 0: 3 else: 1
  let exchanged = logicalCommandExchange(chainPath, policyPath, sourcePath, logicalPolicyPath,
      requests, responses, firstCount, extra)
  if malformed or omitted:
    assert exchanged.outcome.error == (if malformed and
        namespaces: CurrentDownloadCommandResult.InvalidPolicy else: CurrentDownloadCommandResult.InvalidLogicalSource)
    assert exchanged.outcome.adoptedBlocks == 0 and exchanged.secondRequests == 0
  elif keyBytes > CurrentLogicalSourceKeyBytes:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.LogicalSourceExportFailure
    assert exchanged.outcome.adoptedBlocks == 1 and exchanged.secondRequests == 1
    assert readFile(actualSourcePath) == text # A key outside the accepted source syntax never replaces the previous file with an unreadable successful export.
  elif unwritable:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.LogicalSourcePublicationFailure
    assert exchanged.outcome.adoptedBlocks == 1 and exchanged.secondRequests == 1
    assert readFile(actualSourcePath) == text # Ordinary atomic publication refusal preserves the entire previous source file.
  elif partial:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.Exhausted
    assert exchanged.outcome.adoptedBlocks == 1 and exchanged.secondRequests == 2
  elif refused:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.Exhausted
    assert exchanged.outcome.adoptedBlocks == 0 and exchanged.secondRequests == 1
    assert readFile(actualSourcePath) == text, "refusal retains the original identity source"
  else:
    assert exchanged.outcome.error == CurrentDownloadCommandResult.Adopted
    assert exchanged.outcome.adoptedBlocks == firstCount and exchanged.secondRequests == firstCount
  if refresh and not malformed and not omitted and not refused and not unwritable and keyBytes <= CurrentLogicalSourceKeyBytes:
    let updated = readFile(actualSourcePath)
    if keyBytes > 0:
      var key = newSeq[byte](keyBytes)
      key[0] = 9
      assert updated != text and ("k=" & logicalHex(key) & "\n") in
          updated # The exact maximum source key remains restartable.
    elif replacement:
      assert updated != text and "s=99\n" in updated
      let length = if sequential: 0 else: replacementLength
      let expected = "r=" & logicalHex(replacementHash) & ":" & $length & "\n"
      assert expected in updated, "new-generation code request survives source export"
      if postBirth: assert "k=05\n" in updated # Only a producer touch after creation certifies the old raw name.
    elif namespaces:
      assert updated != text and "k=07\n" in updated # Exported raw identity comes only from the actual qualified adopted source.
    else: assert updated == text # Strict identity preservation exports the same canonical declarations after actual adoption.
  if malformed:
    assert not fileExists(database) and not dirExists(
        database) # Lexical refusal precedes Services or database startup.
  elif layout != 0:
    if not omitted and not refused and not unwritable and keyBytes <=
        CurrentLogicalSourceKeyBytes and (not namespaces or refresh):
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
    assert owner.chainView.retainedCount == (if omitted or refused: 1 elif unwritable or keyBytes >
        CurrentLogicalSourceKeyBytes: 2 else: 4)
    for i in 0..<owner.chainView.retainedCount:
      equalCurrentDiskMap(owner.chainView.retainedBlockAt(RetainedBlockIndex(uint64(
          i))).value.stateSnapshot, heads[i].stateSnapshot)
    owner.close()
proc longKeyFixture(base: OwnedReport, length: int): NamespaceExecutionFixture =
  ## A real host reads a long initialized-zero writable/heap span; the compact program and original signed profile remain unchanged.
  var code = @[0'u8]
  for octet in guestEnvelope([registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, uint64(length)), registerImmediate(10, 196608), registerImmediate(11, 1),
      @[10'u8, 5], @[50'u8, 0]], writable = @[9'u8]): code.add(octet)
  var policy = currentConsecutiveLimits()
  policy.completion.execution.initial.guests.copyBytes = MemoryByteLimit(8192)
  policy.completion.execution.execution.round.guests.copyBytes = MemoryByteLimit(8192)
  result = namespaceExecutionFixture(base, namespaceHaltCode(), code, policies = policy)
  var key = newSeq[byte](length)
  key[0] = 9
  let physical = serviceStorageKey(ServiceIndex(99), key, ByteLimit(8192)).value
  assert result.update.currentUpdateState.lookup(physical).value.bytes == @[
      9'u8] # Actual PVM execution must create the claimed long identity before any export witness runs.
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
  let exactKey = longKeyFixture(decodeOwnedReport(bytes, 2).value, CurrentLogicalSourceKeyBytes)
  let oversizedKey = longKeyFixture(decodeOwnedReport(bytes, 2).value,
      CurrentLogicalSourceKeyBytes+1)
  sourceChecks(fixture)
  let replacement = namespaceReplacementFixture(decodeOwnedReport(bytes, 2).value)
  var sequentialPolicy = currentCandidateLimits()
  sequentialPolicy.round.blockGas = Gas(200000)
  let sequential = namespaceSequentialReplacementFixture(decodeOwnedReport(bytes, 2).value,
    sequentialPolicy).toNamespaceExecutionFixture

  var retirementPolicy = currentCandidateLimits()
  retirementPolicy.completion.execution.initial.guests.accountWriteFacts = ElementLimit(16)
  retirementPolicy.completion.execution.initial.accounts.writes.writes = ElementLimit(16)
  let retired = namespaceRetiredReplacementFixture(decodeOwnedReport(bytes, 2).value,
    retirementPolicy).toNamespaceExecutionFixture
  let reusedOrigin = namespaceRetiredReplacementFixture(decodeOwnedReport(bytes, 2).value,
    retirementPolicy, reuse = true)
  let reused = reusedOrigin.toNamespaceExecutionFixture
  let oldCode = reusedOrigin.services[1].metadata.codeHash
  let oldLength = int(uint32(reusedOrigin.services[1].requests[^1].length))
  let orphan = namespaceRetiredReplacementFixture(decodeOwnedReport(bytes, 2).value,
    retirementPolicy, orphan = true).toNamespaceExecutionFixture
  var postBirthPolicy = retirementPolicy
  postBirthPolicy.completion.execution.execution.round.guests.provisions = AccumulationProvisionLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  postBirthPolicy.completion.execution.execution.round.provisions.values = PreimageLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  postBirthPolicy.completion.execution.execution.round.provisions.encodedBytes = ByteLimit(128)
  let postBirth = namespaceRetiredReplacementFixture(decodeOwnedReport(bytes, 2).value,
    postBirthPolicy, postBirth = true).toNamespaceExecutionFixture
  var checkpointPolicy = retirementPolicy
  checkpointPolicy.completion.execution.initial.guests.provisions = AccumulationProvisionLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  checkpointPolicy.completion.execution.initial.provisions.values = PreimageLimits(
    items: ElementLimit(1), perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(1))
  checkpointPolicy.completion.execution.initial.provisions.encodedBytes = ByteLimit(128)
  let checkpoint = namespaceAtomicReplacementFixture(decodeOwnedReport(bytes, 2).value,
    checkpointPolicy).toNamespaceExecutionFixture
  let withoutCheckpoint = namespaceAtomicReplacementFixture(decodeOwnedReport(bytes, 2).value,
    checkpointPolicy, checkpoint = false).toNamespaceExecutionFixture
  let afterBirthCheckpoint = namespaceAtomicReplacementFixture(decodeOwnedReport(bytes, 2).value,
    checkpointPolicy, late = true).toNamespaceExecutionFixture
  let orphanRetirement = namespaceAtomicReplacementFixture(decodeOwnedReport(bytes, 2).value,
    checkpointPolicy, orphan = true).toNamespaceExecutionFixture
  for layout in 0..2:
    command(checkpoint, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, postBirth = true, replacementLength = 0)
    command(checkpoint, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, postBirth = true, replacementLength = 0, partial = true)
    command(checkpoint, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, postBirth = true, replacementLength = 0, omitMembership = true)
    for supported in [withoutCheckpoint, afterBirthCheckpoint]:
      # Atomic ejection evidence survives independently of guest checkpoint placement.
      command(supported, layout, namespaces = true, refresh = true, replacement = true,
        retired = true, postBirth = true, replacementLength = 0)
    command(orphanRetirement, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, postBirth = true, replacementLength = 0, unsupported = true)
    command(postBirth, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, postBirth = true, replacementLength = 0)
    command(postBirth, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, postBirth = true, replacementLength = 0, partial = true)
    command(postBirth, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, postBirth = true, replacementLength = 0, omitMembership = true)
    command(retired, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, replacementLength = 0)
    command(reused, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, replacementLength = oldLength, replacementHash = array[32, byte](oldCode))
    command(reused, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, partial = true, replacementLength = oldLength, replacementHash = array[32,
          byte](oldCode))
    command(orphan, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, unsupported = true)
    command(retired, layout, namespaces = true, refresh = true, replacement = true,
      retired = true, omitMembership = true)
    command(sequential, layout, namespaces = true, refresh = true, replacement = true,
        sequential = true)
    command(sequential, layout, namespaces = true, refresh = true, partial = true,
        replacement = true, sequential = true)
    command(replacement, layout, namespaces = true, refresh = true, replacement = true)
    command(replacement, layout, namespaces = true, refresh = true, partial = true,
        replacement = true)
    command(replacement, layout, namespaces = true, refresh = true, refuse = true,
        replacement = true)
    command(replacement, layout, namespaces = true, refresh = true, omitMembership = true,
        replacement = true)

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
    command(exactKey, layout, namespaces = true, refresh = true,
        keyBytes = CurrentLogicalSourceKeyBytes)
    command(oversizedKey, layout, namespaces = true, refresh = true,
        keyBytes = CurrentLogicalSourceKeyBytes+1)
  echo "PVM current logical startup passed"
try: main()
except: quit(2) # Parser, source matching, command adoption and every native cleanup path are mandatory evidence.
