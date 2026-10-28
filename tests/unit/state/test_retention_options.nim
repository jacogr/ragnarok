# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Historical selection is explicit, aliases agree and failed/partial/light configurations grant no full-state policy.
import std/[assertions, syncio, strutils]
import ../../../src/app/[options, cli_help]
import ../../../src/storage/history_index
proc withControls(base, suffix: seq[string]): seq[string] =
  ## Keep test argument ownership independent without relying on unsupported sequence concatenation.
  result = base
  for value in suffix: result.add(value)
proc main() =
  ## Canonical and process normalization share exactly the same checked retention policy.
  let base = @["server", "--with-state", "--chain", "chain.json"]
  var options = default(Options)
  assert parseCanonicalOptions(base, options)
  assert not options.retentionSpecified and options.retentionPolicy.retainedBlocks == DefaultRetainedBlocks
  for count in ["1", "3", "8", "65", "300", "18446744073709551615"]:
    assert parseCanonicalOptions(withControls(base, @["--retain-blocks", count]), options)
    assert options.retentionSpecified and not options.retentionPolicy.archive
  for alias in [@["--archive"], @["--retain-blocks", "-1"]]:
    assert parseCanonicalOptions(withControls(base, alias), options)
    assert options.retentionSpecified and options.retentionPolicy.archive
  for controls in [@["--retain-blocks", "0"], @["--retain-blocks", "-2"],
      @["--retain-blocks", "+1"], @["--retain-blocks", "18446744073709551616"],
      @["--retain-blocks"], @["--archive", "--retain-blocks", "8"],
      @["--retain-blocks", "-1", "--archive"], @["--archive", "--archive"],
      @["--retain-blocks", "3", "--retain-blocks", "3"]]:
    assert not parseCanonicalOptions(withControls(base, controls), options)
    assert not options.valid and not options.retentionSpecified and
        not options.retentionPolicy.initialized
  assert not parseCanonicalOptions(@["server", "--archive"], options)
  assert not parseCanonicalOptions(withControls(base, @["--state-mode", "light", "--archive",
    "--state-trust", "trust", "--state-header", "header"]), options)
  let process = @["server", "--net-port", "4000", "--net-cert", "cert", "--net-key", "key",
    "--net-peer-key", "-", "--net-alpn", "test", "--with-state", "--chain", "chain.json"]
  assert parseOptions(withControls(process, @["--retain-blocks=-1"]), options)
  assert options.retentionPolicy.archive
  let query = @["history", "--with-state", "--chain", "chain.json", "--state-storage", "disk",
      "--state-db", "db"]
  assert parseOptions(withControls(query, @["--history-ordinal", "18446744073709551615"]), options)
  assert uint64(options.historicalOrdinal) == high(uint64)
  let hash = repeat('a', 64)
  assert parseOptions(withControls(query, @["--history-block", hash, "--history-checkpoint",
      "out.bin"]), options)
  assert options.historicalHash == hash and options.historicalCheckpointPath == "out.bin"
  for controls in [@["--history-ordinal", "0"], @["--history-block", "abcd"],
      @["--history-block", repeat('A', 64)], @["--history-block", hash, "--history-ordinal", "1"],
      @["--history-ordinal", "1", "--archive"], @["--history-ordinal", "1", "--with-rpc"],
      @["--history-ordinal", "1", "--state-migrate-from", "old"],
      @["--history-ordinal", "1", "--history-checkpoint", "db"]]:
    assert not parseOptions(withControls(query, controls), options)
    assert not options.valid
  assert not parseOptions(query, options)
  assert not parseCanonicalOptions(withControls(base, @["--history-block", hash]), options)
  let help = commandHelp("history")
  assert "--history-block" in help and "--history-checkpoint" in help
  assert "--archive" notin help and "--net-port" notin help
  assert "--archive" in commandHelp("server") and "--retain-blocks" in commandHelp("server")
main()
echo "PASS retention options: aliases, full-mode separation, overflow/conflict refusal and offline query controls"
