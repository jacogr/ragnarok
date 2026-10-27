# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Offline command activation, finite shape and explicit trust/state budgets reject unrelated side-effect controls.
import std/[assertions, syncio]
import ../../../src/app/[options, trace_check_command]
import ../../../src/codec/bounded
proc main() =
  ## Parsing is atomic and cannot silently enable listeners, disk ownership, recovery or download behavior for a trace check.
  let missing = default(TraceCheckCommandOutcome)
  assert missing.error == TraceCheckCommandError.Uninitialized
  assert missing.checkedBlocks == 0 and missing.requestedBlocks == 0
  var options = default(Options)
  assert runTraceChecks(options).error == TraceCheckCommandError.InvalidArguments
  let base = @["check-traces", "absent-trace-check-policy.txt", "genesis.bin", "step.bin",
      "--with-state", "--chain", "chain.json"]
  assert parseCanonicalOptions(base, options)
  assert options.stateEnabled and options.argumentCount == 4
  let refused = runTraceChecks(options)
  assert refused.error == TraceCheckCommandError.FileFailure
  assert refused.requestedBlocks == 1 and refused.checkedBlocks == 0
  for extra in [@["--with-rpc"], @["--rpc-port", "9001"], @["--with-ui"],
      @["--state-storage", "memory"], @["--state-storage", "disk", "--state-db", "db"],
      @["--with-management", "--management-socket", "management.sock"],
      @["--with-telemetry", "--telemetry-endpoint", "127.0.0.1:9000"],
      @["--download-blocks", "2"], @["--download-ancestor", "old-header.bin"]]:
    var arguments = base
    for item in extra: arguments.add(item) # Every unrelated explicit control must be refused before file or service activity.
    assert not parseCanonicalOptions(arguments, options)
    assert not options.valid
  assert not parseCanonicalOptions(@["check-traces", "policy", "genesis", "step", "--chain",
      "chain.json"], options)
  assert not parseCanonicalOptions(@["check-traces", "policy", "genesis", "--with-state", "--chain",
      "chain.json"], options)
  var many = @["check-traces", "policy", "genesis"]
  for index in 0..<256: many.add("step.bin") # Fixed command cardinality bounds even repeated filenames independently of wire counts.
  for item in ["--with-state", "--chain", "chain.json"]: many.add(item)
  assert parseCanonicalOptions(many, options)
  var excessive = @["check-traces", "policy", "genesis", "another.bin"]
  for index in 0..<256: excessive.add("step.bin")
  for item in ["--with-state", "--chain", "chain.json"]: excessive.add(item)
  assert not parseCanonicalOptions(excessive, options)
  var zero = base
  for item in ["--state-writes", "0", "--state-write-bytes", "0"]: zero.add(item)
  assert parseCanonicalOptions(zero, options)
  assert uint64(options.stateWrites) == 0 and uint64(options.stateWriteBytes) == 0
  echo "PASS offline trace command: finite explicit configuration and strict control scope"
main()
