# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_download_policy_arc_release"}

## Every current resource leaf is mandatory; canonical numeric/boolean decoding stays atomic and decoded policies drive genuine current preparation.
import std/assertions
import std/syncio
import std/envvars
import std/strutils
import std/posix/posix
import ../../../src/app/current_download_policy as app_current_download_policy
import ../../../src/app/download_policy as app_download_policy
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/candidate as app_candidate
import ../../../src/app/chain as app_chain
import ../../../src/app/download_schedule as app_download_schedule
import ../../../src/quic/current_block_download_loop as quic_current_block_download_loop
import ../../../src/quic/current_block_download_stream as quic_current_block_download_stream
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../support/state_current_services_disk_samples
import ../../support/state_accumulation_current_chain_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/testing_arc_evidence
proc policy(): CurrentDownloadLoopLimits =
  ## Authored stage policies are independent caller choices, including explicit discovery permission.
  CurrentDownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(10)), input: CurrentBlockInputLimits(blockBytes: ByteLimit(
        100000),
      ancestorBytes: ByteLimit(10000), ancestors: ElementLimit(4), discoverAncestors: true),
    candidate: currentCandidateLimits(), stream: CurrentDownloadStreamLimits(readBytes: ByteLimit(73),
      writeBytes: ByteLimit(3), timeout: CurrentDownloadTimeout(5000)),
    attemptTimeout: CurrentDownloadAttemptTimeout(10000))
proc replaceField(text, name, value: string): string =
  ## The independent test scanner replaces exactly one authored complete row without production parsing or schema visitors.
  result = ""
  var changed = false
  for row in text.splitLines():
    if row.len == 0: continue
    let separator = row.find('=')
    if separator > 0 and row.substr(0, separator-1) == name:
      assert not changed
      result.add(name & "=" & value & "\n")
      changed = true
    else:
      result.add(row & "\n") # Preserve the independent header and every other explicit row.
  assert changed, "actual authored current policy row " & name
proc parser(text: string) =
  ## Every missing leaf and malformed document must fail without exposing any parsed prefix.
  let good = decodeCurrentDownloadPolicy(text)
  assert good.error == CurrentDownloadPolicyError.None
  assert encodeCurrentDownloadPolicy(good.value) == text
  assert uint64(good.value.candidate.completion.execution.execution.entries) ==
      uint64(policy().candidate.completion.execution.execution.entries)
  assert uint64(good.value.candidate.completion.composition.statistics.gas) ==
      uint64(policy().candidate.completion.composition.statistics.gas)
  assert uint64(good.value.candidate.completion.composition.consensus.totalBytes) ==
      uint64(policy().candidate.completion.composition.consensus.totalBytes)
  assert good.value.input.discoverAncestors
  let rows = text.splitLines()
  assert rows.len == 391, "current header, 389 explicit leaves and trailing newline"
  for missing in 1..<rows.high:
    var incomplete = rows[0] & "\n"
    for index in 1..<rows.high:
      if index != missing: incomplete.add(rows[index] & "\n") # Independently omit every mandatory field.
    let refused = decodeCurrentDownloadPolicy(incomplete)
    assert refused.error == CurrentDownloadPolicyError.MissingField
    assert refused.fieldName == rows[missing].substr(0, rows[missing].find('=')-1)
  assert decodeCurrentDownloadPolicy(text.replace("schedule.peers=1",
      "schedule.unknown=1")).error == CurrentDownloadPolicyError.UnknownField
  assert decodeCurrentDownloadPolicy(text & "schedule.peers=1\n").error ==
      CurrentDownloadPolicyError.DuplicateField
  for number in ["", "-1", "+1", "01", "1.0", "1e1", "18446744073709551616", " 1", "1 "]:
    assert decodeCurrentDownloadPolicy(replaceField(text, "schedule.attempts", number)).error ==
        CurrentDownloadPolicyError.InvalidNumber
  assert decodeCurrentDownloadPolicy(replaceField(text, "schedule.attempts",
      "18446744073709551615")).value.schedule.attempts == high(uint64)
  assert decodeCurrentDownloadPolicy(replaceField(text,
    "candidate.completion.execution.initial.guests.initialization.pages", "4294967296")).error ==
        CurrentDownloadPolicyError.InvalidNumber
  assert decodeCurrentDownloadPolicy(replaceField(text, "input.discoverAncestors", "2")).error ==
      CurrentDownloadPolicyError.InvalidNumber
  assert not decodeCurrentDownloadPolicy(replaceField(text, "input.discoverAncestors",
      "0")).value.input.discoverAncestors
  for name in ["schedule.peers", "schedule.attempts", "schedule.retryDelay", "input.blockBytes",
      "stream.readBytes", "stream.writeBytes", "stream.timeout", "attemptTimeout"]:
    assert decodeCurrentDownloadPolicy(replaceField(text, name, "0")).error ==
        CurrentDownloadPolicyError.InvalidPolicy
  assert decodeCurrentDownloadPolicy(replaceField(text, "stream.readBytes", "4097")).error ==
      CurrentDownloadPolicyError.InvalidPolicy
  assert decodeCurrentDownloadPolicy(replaceField(text, "stream.writeBytes", "43")).error ==
      CurrentDownloadPolicyError.InvalidPolicy
  assert decodeCurrentDownloadPolicy(replaceField(text, "schedule.peers", "17")).error ==
      CurrentDownloadPolicyError.InvalidPolicy
  assert decodeCurrentDownloadPolicy(text.substr(0, text.high-1)).error ==
      CurrentDownloadPolicyError.None
  assert decodeCurrentDownloadPolicy(text & "# bounded comment\n\n").error ==
      CurrentDownloadPolicyError.None
  assert decodeCurrentDownloadPolicy(repeat('x', CurrentDownloadPolicyBytes+1)).error ==
      CurrentDownloadPolicyError.LimitExceeded
  for invalid in ["", "other\n", "\n", text & "not a key=1\n", text & "name=1=2\n"]:
    assert decodeCurrentDownloadPolicy(invalid).error != CurrentDownloadPolicyError.None
  let legacy = text.replace("ragnarok-current-download-policy-v1", "ragnarok-download-policy-v1")
  assert decodeCurrentDownloadPolicy(legacy).error == CurrentDownloadPolicyError.WrongVersion
  assert decodeDownloadPolicy(text).error == DownloadPolicyError.WrongVersion
proc files(text: string) {.raises.} =
  ## Bounded file loading preserves typed IO/size/version failures and never falls back to old policies.
  var path = "pvm-current-download-policy.conf"
  defer: discard posix.unlink(path.toCString())
  assert loadCurrentDownloadPolicy("").error == CurrentDownloadPolicyError.FileFailure
  writeFile(path, text)
  assert loadCurrentDownloadPolicy(path).error == CurrentDownloadPolicyError.None
  writeFile(path, repeat('x', CurrentDownloadPolicyBytes+1))
  assert loadCurrentDownloadPolicy(path).error == CurrentDownloadPolicyError.LimitExceeded
  writeFile(path, "ragnarok-download-policy-v1\n")
  assert loadCurrentDownloadPolicy(path).error == CurrentDownloadPolicyError.WrongVersion
  assert posix.unlink(path.toCString()) == 0
  assert loadCurrentDownloadPolicy(path).error == CurrentDownloadPolicyError.FileFailure
proc execute(context: CurrentChainFixture, text: string, tiny: bool) =
  ## Decoded independent policies govern actual signed current execution and sealed-child capture, not just round-trip text.
  let parsed = decodeCurrentDownloadPolicy(if tiny: replaceField(text, "candidate.headerBytes",
      "1") else: text)
  assert parsed.error == CurrentDownloadPolicyError.None
  let configured = parsed.value
  let owner = initApplicationChain(context.currentChainSeeded).value
  let wire = context.currentDiskChildBytes
  var input = default(CurrentBlockInput)
  let admitted = input.begin(owner, ByteLimit(uint64(wire.len)), context.older,
    configured.input, configured.candidate)
  assert admitted.error == CurrentBlockInputError.None
  assert input.append(admitted.value, wire, true) == CurrentBlockInputError.None
  let completed = input.prepare(admitted.value, owner)
  if tiny:
    assert completed.error == CurrentBlockInputError.PreparationFailure
    assert completed.preparationFailure.error == CurrentCandidateError.PreparationFailure
  else:
    assert completed.error == CurrentBlockInputError.None
    equalCurrentDiskMap(completed.value.currentUpdateState,
        context.source.currentConsensusState.value)
proc cycle(text: string) =
  ## Plain policy copies cannot mutate a parsed snapshot; failure retains only bounded diagnostics.
  let parsed = decodeCurrentDownloadPolicy(text)
  assert parsed.error == CurrentDownloadPolicyError.None
  var copied = parsed.value
  copied.schedule.attempts = 99
  copied.input.discoverAncestors = false
  assert parsed.value.schedule.attempts == 1 and parsed.value.input.discoverAncestors
  assert decodeCurrentDownloadPolicy(text & "schedule.peers=1\n").error ==
      CurrentDownloadPolicyError.DuplicateField
proc main() {.raises.} =
  ## Lexical/atomicity/ownership witnesses precede independently signed current execution under decoded ceilings.
  let text = encodeCurrentDownloadPolicy(policy())
  assert text.len <= CurrentDownloadPolicyBytes
  parser(text)
  files(text)
  cycle(text)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(text)
  let after = getOccupiedMem()
  assert before == after, "current policy releases"
  recordArcRelease("pvm_current_download_policy", 1000, before, after)
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, uses = 2, available = true)
  execute(context, text, false)
  execute(context, text, true)
  echo "PVM current download policy passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit(2) # Fixture, IO or current execution errors cannot satisfy successful policy authority.
