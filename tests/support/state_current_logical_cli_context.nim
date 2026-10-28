# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit logical startup policies, independent identity files and forked authenticated responders exercise the production command.
import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import std/times
import std/os
import std/strutils
import std/posix/posix
import ./state_parent_profile_context
import ./state_parent_globals_context
import ./codec_supplied_logical_context
import ./state_current_identity_context
import ./state_current_namespace_refresh_context
import ./state_current_namespace_execution_context
import ./state_current_application_context
import ./state_current_consecutive_context
import ./state_current_consecutive_download_context
import ./state_current_download_command_context
import ./state_current_services_disk_samples
import ./app_block_download_transport
import ../../src/app/current_logical_startup as app_current_logical_startup
import ../../src/app/current_logical_download as app_current_logical_download
import ../../src/app/current_download_policy as app_current_download_policy
import ../../src/app/current_download_command as app_current_download_command
import ../../src/app/options as app_options
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/block_codec as codec_block_codec
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/block_admission as state_block_admission
import ../../src/state/report_admission as state_report_admission
proc logicalStartupTestLimits*(): CurrentLogicalStartupLimits =
  ## Startup source/profile/matching budgets remain independent of all later continuation ceilings.
  CurrentLogicalStartupLimits(projection: namespaceRefreshLimits.projection,
      profile: parentProfileTestLimits, globals: parentGlobalsTestLimits,
      logical: suppliedLogicalTestLimits,
      download: CurrentLogicalDownloadLimits(identities: currentIdentityTestLimits,
          requests: namespaceRequestLimits,

reconstruction: namespaceRefreshLimits, logical: namespaceLogicalLimits()))
proc logicalHex*(bytes: openArray[byte]): string =
  ## Independent lowercase serializer preserves empty original raw keys without a sentinel.
  const digits = "0123456789abcdef"
  result = ""
  for value in bytes:
    result.add(digits[int(value shr 4)])
    result.add(digits[int(value and 15)])
proc logicalDeclarationText*(services: openArray[StateService]): string =
  ## File carries identities only; metadata, storage values, preimages and histories must come from the actual selected source.
  result = "ragnarok-current-logical-source-v1\n"
  for service in services:
    result.add("s=" & $uint32(service.service) & "\n")
    for item in service.storage: result.add("k=" & logicalHex(item.key) & "\n")
    for item in service.preimages: result.add("p=" & logicalHex(array[32, byte](item.hash)) & "\n")
    for item in service.requests:
      result.add("r=" & logicalHex(array[32, byte](item.hash)) & ":" & $uint32(item.length) & "\n")
proc logicalCommandExchange*(chainPath, policyPath, sourcePath, logicalPolicyPath: string,
    requests: seq[array[42, byte]], responses: seq[seq[byte]], count: int,
    extra: seq[string]): CurrentDownloadExchange {.raises.} =
  ## Independent child polls actual pinned TLS responders while the original process executes the real command and joined Services lifecycle.
  result = default(CurrentDownloadExchange) # Initialize every scalar outcome even along the fork child's nonreturning OS path.
  var servers = default(DownloadResponders)
  var modes = newSeq[DownloadTransferMode](requests.len)
  for i in 0..<modes.len: modes[i] = Healthy
  assert servers.openSequenceResponders(requests, responses, modes), "logical TLS responders opened"
  let port = servers.port(true)
  let stopPath = "logical-cli-stop"
  let countPath = "logical-cli-count"
  var stop = stopPath
  discard posix.unlink(stop.toCString())
  defer:
    for name in [stopPath, countPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Remove only exact test-owned control files after joining the responder.
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists(stopPath) and (getMonoTime()-started).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3)
      yieldCurrentDiskThread()
    let first = servers.requestCount(false)
    let second = servers.requestCount(true)
    servers.close()
    writeFile(countPath, $first & ":" & $second)
    posix.exitnow(0) # Never destroy inherited parent ARC/native owners after fork.
  servers.close()
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var state = 0.cint
      discard posix.waitpid(child, state, 0)
  var arguments = currentCommandArguments(port, count, chainPath, policyPath, extra)
  for arg in ["--download-logical-source", sourcePath, "--download-logical-policy",
      logicalPolicyPath]: arguments.add(arg)
  var options = default(Options)
  assert parseCanonicalOptions(arguments, options), "complete logical command arguments accepted"
  let outcome = runCurrentDownloads(options)
  writeFile(stopPath, "stop")
  var state = 0.cint
  let waited = posix.waitpid(child, state, 0)
  assert waited == child, "logical responder reaped"
  reaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0, "logical responder joined without callback failure"
  let counts = readFile(countPath)
  let separator = counts.find(':')
  assert separator > 0 and separator < counts.len-1, "logical responder reported exact request counts"
  result = CurrentDownloadExchange(outcome: outcome, firstRequests: parseInt(counts.substr(0,
      separator-1)), secondRequests: parseInt(counts.substr(separator+1)))
