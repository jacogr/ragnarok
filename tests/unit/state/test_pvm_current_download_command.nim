# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The explicit current command performs real authenticated current execution and durable/RPC adoption with atomic option/policy preflight.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[current_download_command, current_download_policy, options, services]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/accumulation_current_consensus
import ../../../src/storage/managed_manifest
import ../../support/[accumulation_current_chain_context, current_download_command_context,
  current_services_disk_samples, managed_storage_samples, block_download_transport, rpc_socket]
const ChainPath = "pvm-current-download-command-chain"
const PolicyPath = "pvm-current-download-command-policy"
proc optionsTests() {.raises.} =
  ## Both command pipelines accept the shared shape; current mode still requires state, rejects telemetry and owns discovery intent.
  var options = default(Options)
  assert not parseCanonicalOptions(@["download-current"], options)
  assert not parseCanonicalOptions(@["server", "--download-blocks", "2", "--with-state", "--chain",
      "selected"], options)
  assert parseCanonicalOptions(@["download-current", "--with-state", "--chain", "selected",
      "--download-blocks", "2"], options)
  assert options.downloadBlocks == 2
  assert parseCanonicalOptions(@["download-current", "--with-state", "--chain", "selected",
      "--download-discover-ancestors", "2"], options)
  assert options.discoverDownloadAncestors == 2
  assert not parseCanonicalOptions(@["download-current", "--with-state", "--chain", "selected",
    "--download-remote-ancestors", "1",
    "--download-discover-ancestors", "1"], options)
  assert runCurrentDownloads(default(Options)).error == CurrentDownloadCommandResult.InvalidOptions
proc check(context: CurrentChainFixture, disk, managed, rpc: bool) {.raises.} =
  ## API entry uses actual TLS/current worker execution; strict restart proves every selected durable state entry.
  var database = "pvm-current-download-command-state"
  defer:
    if disk:
      if managed: removeManagedSample(database, [ManagedEpoch(1)])
      else: discard posix.unlink(database.toCString())
  var extra: seq[string] = @[]
  if disk: extra = @["--state-storage", "disk", "--state-db", database]
  if managed:
    extra.add("--state-layout")
    extra.add("managed")
    extra.add("--state-compact-bytes")
    extra.add("0") # Exact publication lifetime remains separate from maintenance ordering witnesses.
  if rpc:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    extra.add("--with-rpc")
    extra.add("--rpc-port")
    extra.add($reserved.port)
  let observed = exchangeCurrentDownloads(context, @[context.currentResponseFrame], @[Healthy], 1,
    currentCommandLimits(), ChainPath, PolicyPath, "pvm-current-download-command", extra)
  assert observed.outcome.error == CurrentDownloadCommandResult.Adopted, "real current command adoption"
  assert observed.outcome.requestedBlocks == 1 and observed.outcome.adoptedBlocks == 1
  assert observed.firstRequests == 0 and observed.secondRequests == 1
  if disk:
    var owner = default(Services)
    defer: owner.close()
    assert owner.start(currentDiskOptions(ChainPath, database, managed, 0), "strict current command restart")
    equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
    assert owner.chainView.retainedCount == 2
    owner.close()
proc preflight(context: CurrentChainFixture) {.raises.} =
  ## Version/mode/endpoint refusals occur before any Services listener/database or native outgoing endpoint can open.
  var options = default(Options)
  let arguments = currentCommandArguments(1, 1, ChainPath, PolicyPath)
  assert parseCanonicalOptions(arguments, options)
  writeFile(PolicyPath, "ragnarok-download-policy-v1\n")
  assert runCurrentDownloads(options).error == CurrentDownloadCommandResult.InvalidPolicy
  writeFile(PolicyPath, encodeCurrentDownloadPolicy(currentCommandLimits(true)))
  assert runCurrentDownloads(options).error == CurrentDownloadCommandResult.InvalidPolicy
  var policy = currentCommandLimits()
  policy.schedule.peers = ElementLimit(0)
  writeFile(PolicyPath, encodeCurrentDownloadPolicy(policy))
  assert runCurrentDownloads(options).error == CurrentDownloadCommandResult.InvalidPolicy
proc main() {.raises.} =
  ## Independent signed current fixtures qualify production command selection without legacy certificate conversion.
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString())
  optionsTests()
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  preflight(context)
  check(context, false, false, false)
  check(context, true, false, false)
  check(context, true, false, true)
  check(context, true, true, false)
  check(context, true, true, true)
try:
  main()
except:
  quit(2) # Startup, native process, current execution and durable restart failures cannot satisfy command authority.
echo "PVM current download command passed"
