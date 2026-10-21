# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External checkpoint controls form one explicit atomic group with independent full-width resource policy.
import std/[assertions, syncio]
import ../../../src/app/options
import ../../../src/codec/bounded
proc base(command = "server"): seq[string] =
  ## Existing complete-state activation and mutation limits remain mandatory.
  @[command, "--with-state", "--chain", "chain.json", "--state-writes", "0", "--state-write-bytes", "0"]
proc complete(number = "100000"): seq[string] =
  ## Paths do not supply policy and policy does not imply independent trust.
  @["--state-checkpoint", "state.bin", "--state-trust", "trust.bin", "--state-header", "header.bin",
      "--state-checkpoint-bytes", number]
proc appended(left, right: seq[string]): seq[string] =
  ## Preserve owned parser input without relying on mutable sharing.
  result = left
  for value in right:
    result.add(value) # Each complete tuple retains exact original argument order.
proc main() =
  ## Every partial subset, duplicate, malformed budget and disabled use clears the whole prior configuration.
  var options = default(Options)
  assert not options.recoveryEnabled
  assert parseOptions(base(), options) and not options.recoveryEnabled
  let group = complete()
  assert parseOptions(appended(base(), group), options)
  assert options.recoveryEnabled and options.recoveryPath == "state.bin"
  assert options.recoveryTrustPath == "trust.bin" and options.recoveryHeaderPath == "header.bin"
  assert uint64(options.recoveryByteLimit) == 100000
  for mask in 1..<15:
    var partial = base()
    for index in 0..<4:
      if (mask and (1 shl index)) != 0:
        partial.add(group[index * 2])
        partial.add(group[index * 2 + 1]) # Only complete option/value pairs enter each partial subset.
    assert not parseOptions(partial, options)
    assert not options.valid and not options.recoveryEnabled
  for index in 0..<4:
    var duplicate = appended(base(), group)
    duplicate.add(group[index * 2])
    duplicate.add(group[index * 2 + 1])
    assert not parseOptions(duplicate, options) # Every individual recovery control obeys existing uniqueness rules.
  for malformed in ["", "-1", "+1", "1.0", " 1", "1 ", "18446744073709551616",
      "000000000000000000000"]:
    assert not parseOptions(appended(base(), complete(malformed)), options)
    assert not options.valid # No previously valid import path/budget survives refusal.
  for valid in ["0", "1", "0001", "18446744073709551615"]:
    assert parseOptions(appended(base(), complete(valid)), options)
    assert options.recoveryEnabled # Full-width policy is preserved without narrowing to a host extent.
  assert uint64(options.recoveryByteLimit) == high(uint64)
  assert not parseOptions(appended(@["server"], group), options)
  assert not parseOptions(appended(@["server", "--chain", "chain.json", "--with-rpc"], group), options)
  assert not parseOptions(appended(base("--version"), group), options)
  for command in ["server", "client", "mesh", "download"]:
    assert parseOptions(appended(base(command), group),
        options) # Recovery selects no additional listener or telemetry service.
    assert options.rpcPort == 0 and not options.telemetryEnabled
  var mutableInput = appended(base(), group)
  assert parseOptions(mutableInput, options)
  let saved = options
  mutableInput[mutableInput.high - 6] = "changed-state.bin"
  assert options.recoveryPath == "state.bin" and saved.recoveryPath == "state.bin"
  assert parseOptions(base(), options) and not options.recoveryEnabled
  assert saved.recoveryEnabled and saved.recoveryHeaderPath == "header.bin"
  echo "PASS application recovery options: atomic complete controls, explicit activation, full-width limits and owned paths"
main() # All parser checks are independent of files, sockets and crypto providers.
