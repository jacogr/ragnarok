# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Named CLI witnesses verify help/default agreement, ordered groups, canonical names, failures and owner release.
# @@Verification={"arc": "app_cli_arc_release"}

import std/[assertions, syncio, strutils]
import ../../../src/app/options
import ../../../src/app/cli/[help as cli_help, commands as cli_commands]
import ../../../src/codec/bounded
import ../../../src/lib/logging
import ../../support/arc_evidence

proc peer(command = "server"): seq[string] =
  ## Name each transport input; service flags can be interleaved without changing their ownership.
  result = @[command, "--net-port", "4000", "--net-cert", "node.pem", "--net-key", "node.key",
      "--net-peer-key", "-", "--net-alpn", "network"]
  if command == "server":
    result.add("--net-mode"); result.add("valid")

proc parsed(input: seq[string]): Options =
  ## Fail with the parser's original diagnostic instead of hiding the relevant field behind a helper assertion.
  result = default(Options)
  var diagnostic = ""
  assert parseOptions(input, result, diagnostic), diagnostic
  assert diagnostic.len == 0, "CLI invariant: diagnostic.len == 0"

let bareServer = parsed(@["server"])
assert bareServer.argument(2) == "34100" and bareServer.argument(3).endsWith("data/network/cert.pem")
assert bareServer.argument(4).endsWith("data/network/key.pem") and bareServer.argument(5) == "-"
assert bareServer.argument(6) == DefaultDevelopmentAlpn
assert bareServer.argument(7) == "0" and bareServer.argument(8) == "listen"
let diskDefault = parsed(@["server", "--data-dir", "custom", "--with-state", "--state-storage", "disk"])
assert diskDefault.chainPath == DefaultChainFile and diskDefault.stateDatabase == "custom/full/state.db"
let lightDefault = parsed(@["server", "--data-dir", "custom", "--with-state", "--state-mode",
    "light", "--state-storage", "disk", "--state-trust", "trust", "--state-header", "header"])
assert lightDefault.pagedStorage and lightDefault.stateDatabase == "custom/light/paged"
let managedDefault = parsed(@["server", "--with-state", "--state-storage", "disk", "--state-layout", "managed"])
assert managedDefault.stateDatabase == "./data/full/managed"
assert "default: 34100" in commandHelp("server")
assert "--data-dir DIR" in commandHelp("server")
let named = parsed(peer())
assert named.argumentCount == 8, "CLI invariant: named.argumentCount == 8"
assert named.argument(2) == "4000" and named.argument(3) == "node.pem", "CLI invariant: named.argument(2) == \"4000\" and named.argument(3) == \"node.pem\""
assert named.argument(7) == "10000" and named.argument(8) == "valid", "CLI invariant: named.argument(7) == \"10000\" and named.argument(8) == \"valid\""
let ui = parsed(@["server", "--with-ui", "--net-port=4000", "--net-cert", "node.pem", "--ui-port", "9000",
  "--net-key", "node.key", "--net-peer-key=-", "--net-alpn", "network", "--ui-dev-dir", "public"])
assert ui.uiPort == 9000 and ui.rpcPort == 9418 and ui.devUiDirectory == "public", "CLI invariant: ui.uiPort == 9000 and ui.rpcPort == 9418 and ui.devUiDirectory == \"public\""
var stateInput = peer()
for word in ["--with-state", "--chain", "chain.json"]: stateInput.add(word)
let state = parsed(stateInput)
assert uint64(state.stateWrites) == 1000 and uint64(state.stateWriteBytes) == 100000, "CLI invariant: uint64(state.stateWrites) == 1000 and uint64(state.stateWriteBytes) == 100000"
assert state.nodeMode == NodeMode.Full, "CLI invariant: state.nodeMode == NodeMode.Full"
let overview = commandHelp()
for text in ["default: 9418", "default: 8418", "default: 1000", "default: 100000",
  "default: journal", "default: memory", "default: full", "default: info"]:
  assert text in overview, "CLI invariant: text in overview"
for pair in [("--with-ui", "--ui-port"), ("--ui-port", "--ui-dev-dir"),
    ("--with-rpc", "--rpc-port"), ("--with-management", "--management-socket"),
    ("--with-telemetry", "--telemetry-endpoint"), ("--with-state", "--state-mode")]:
  assert overview.find(pair[0]) < overview.find(pair[1]), "CLI invariant: overview.find(pair[0]) < overview.find(pair[1])"
assert "server|client PORT" notin overview, "CLI invariant: \"server|client PORT\" notin overview"
assert "--download-policy FILE" in commandHelp("download-current"), "CLI invariant: \"--policy FILE\" in commandHelp(\"download-current\")"
assert "--net-peer PORT:KEY_FILE" in commandHelp("download"), "CLI invariant: \"--net-peer PORT:KEY_FILE\" in commandHelp(\"download\")"
assert "--trace-file FILE" in commandHelp("check-traces"), "CLI invariant: \"--trace-file FILE\" in commandHelp(\"check-traces\")"
assert "--download-blocks" notin commandHelp("server"), "CLI invariant: \"--download-blocks\" notin commandHelp(\"server\")"
assert "--with-ui" notin commandHelp("check-traces"), "CLI invariant: \"--with-ui\" notin commandHelp(\"check-traces\")"
assert "--with-state" notin commandHelp("tiny-devnet node"), "CLI invariant: \"--with-state\" notin commandHelp(\"tiny-devnet node\")"
assert "default: 4194304" in commandHelp("serve-fuzz"), "CLI invariant: \"default: 4194304\" in commandHelp(\"serve-fuzz\")"
assert commandHelp("typo").len == 0, "CLI invariant: commandHelp(\"typo\").len == 0"
var topic = "unrelated"
assert helpRequest(@["server", "--help"], topic) and topic == "server", "CLI invariant: helpRequest(@[\"server\", \"--help\"], topic) and topic == \"server\""
assert helpRequest(@["help", "tiny-devnet", "node"], topic) and topic == "tiny-devnet node", "CLI invariant: helpRequest(@[\"help\", \"tiny-devnet\", \"node\"], topic) and topic == \"tiny-devnet node\""
assert helpRequest(@["-h"], topic) and topic == "", "CLI invariant: helpRequest(@[\"-h\"], topic) and topic == \"\""
assert helpRequest(@["tiny-devnet", "--help"], topic) and topic == "tiny-devnet", "CLI invariant: helpRequest(@[\"tiny-devnet\", \"--help\"], topic) and topic == \"tiny-devnet\""
assert not helpRequest(peer(), topic), "CLI invariant: not helpRequest(peer(), topic)"

proc normalized(input, expected: seq[string]) =
  ## Dedicated command adapters receive exactly one owned canonical shape, in declared repeated-value order.
  var output: seq[string] = @[]
  var diagnostic = ""
  assert normalizeCommand(input, output, diagnostic), diagnostic
  assert output == expected, "CLI invariant: output == expected"
normalized(@["check-traces", "--trace-policy", "policy", "--trace-genesis", "genesis",
  "--trace-file", "step", "--with-state"],
  @["check-traces", "policy", "genesis", "step", "--with-state", "--chain", "./chain.json"])
normalized(@["mesh", "--net-remote-port", "4001", "--net-local-port", "4000", "--net-cert", "cert",
  "--net-key", "key",
  "--net-peer-key", "remote", "--net-local-key", "local", "--net-alpn", "network", "--net-gate",
  "ready"],
  @["mesh", "4000", "4001", "cert", "key", "local", "remote", "network", "ready"])
normalized(@["check-traces", "--trace-file", "first.bin", "--trace-policy", "policy",
  "--trace-genesis", "genesis",
  "--trace-file", "second.bin", "--with-state", "--chain", "chain"],
  @["check-traces", "policy", "genesis", "first.bin", "second.bin", "--with-state", "--chain", "chain"])
var download = peer("download-current")
for word in ["--download-policy", "policy", "--net-peer", "4001:peer:key", "--with-state",
    "--chain", "chain"]:
  download.add(word)
let downloads = parsed(download)
assert downloads.argument(8) == "policy" and downloads.argument(9) == "4001", "CLI invariant: downloads.argument(8) == \"policy\" and downloads.argument(9) == \"4001\""
assert downloads.argument(10) == "peer:key" and downloads.downloadBlocks == 1, "CLI invariant: downloads.argument(10) == \"peer:key\" and downloads.downloadBlocks == 1"
# Continuous sync has its own lifecycle controls and refuses finite totals or partial light execution.
var syncInput = peer("sync-current")
for word in ["--download-policy", "policy", "--with-state", "--chain", "chain",
    "--sync-source-age-ms", "1234", "--sync-reconnect-ms", "567"]: syncInput.add(word)
let syncOptions = parsed(syncInput)
assert syncOptions.argument(1) == "sync-current" and syncOptions.syncSourceAgeMs == 1234
assert syncOptions.syncReconnectMs == 567
assert "Runs until SIGINT/SIGTERM" in commandHelp("sync-current")
for extra in [@["--download-blocks", "2"], @["--sync-source-age-ms", "0"],
    @["--state-mode", "light", "--state-trust", "trust", "--state-header", "header"]]:
  var refused = default(Options)
  var input = syncInput
  for word in extra: input.add(word) # Append through the maintained sequence API.
  assert not parseOptions(input, refused)
  assert not refused.valid # A failed repeated or inappropriate control clears earlier configuration.
var unrelated = peer()
for word in ["--sync-reconnect-ms", "100"]: unrelated.add(word)
var refusedSyncControl = default(Options)
assert not parseOptions(unrelated, refusedSyncControl)
normalized(@["tiny-devnet", "init", "--devnet-output", "chain.json"], @["tiny-devnet", "init", "chain.json"])
normalized(@["tiny-devnet", "identity", "--devnet-index", "3"], @["tiny-devnet", "identity", "3"])
normalized(@["tiny-devnet", "node", "--devnet-dir", "data", "--devnet-index", "0",
  "--devnet-base-port", "4000",
  "--devnet-start-unix-ms", "1000", "--devnet-stop-slot", "2", "--devnet-policy", "policy"],
  @["tiny-devnet", "node", "data", "0", "4000", "1000", "2", "policy"])
normalized(@["fuzz"], @["fuzz", "1000", "4194304"])
normalized(@["fuzz", "--fuzz-spec=full", "--fuzz-data-path", "/tmp/data",
  "--fuzz-sock-path", "/tmp/socket", "--fuzz-log-level", "debug"],
  @["fuzz", "1000", "4194304", "--fuzz-spec", "full", "--fuzz-data-path", "/tmp/data",
    "--fuzz-sock-path", "/tmp/socket", "--fuzz-log-level", "debug"])
for name in ["JAM_FUZZ_SPEC", "JAM_FUZZ_DATA_PATH", "JAM_FUZZ_SOCK_PATH", "JAM_FUZZ_LOG_LEVEL"]:
  assert name in commandHelp("fuzz"), "Fuzz help names every environment equivalent"
assert "--fuzz-policy" notin commandHelp("fuzz"), "Built-in fuzz needs no policy file"
normalized(@["serve-fuzz", "--fuzz-policy", "policy", "--fuzz-parameters", "params"],
  @["serve-fuzz", "policy", "params", "1000", "4194304"])
normalized(@["serve-fuzz-preset", "--fuzz-state-write-bytes", "0", "--fuzz-policy", "policy"],
  @["serve-fuzz-preset", "policy", "1000", "0"])

# Canonical spellings work; removed aliases are unknown at both process and component boundaries.
var canonicalInput = peer()
for word in ["--state-mode", "full", "--ui-dev-dir", "public", "--telemetry-endpoint",
    "collector"]: canonicalInput.add(word)
let canonical = parsed(canonicalInput)
assert canonical.nodeMode == NodeMode.Full and canonical.devUiDirectory == "public"
assert canonical.telemetryEndpoint == "collector"
for alias in ["--telemetry", "--dev-ui-dir", "--node-mode"]:
  var input = peer()
  input.add(alias)
  input.add("value")
  var output = default(Options)
  var diagnostic = ""
  assert not parseOptions(input, output, diagnostic), "Removed alias accepted: " & alias
  assert diagnostic == "Unknown option: " & alias, diagnostic
  assert not output.valid and output.argumentCount == 0
  assert not parseCanonicalOptions(@["server", "--ui-port", "9000", alias, "value"], output,
      diagnostic), "Removed alias accepted in service controls: " & alias
  assert diagnostic == "Unknown option: " & alias, diagnostic
for input in [@["server", "4000", "node.pem", "node.key", "-", "network", "10000"],
    @["server", "--net-port"], @["client", "--net-port", "4000"],
    @["server", "4000", "--net-port", "4001"], @["server", "--typo"],
    @["client", "--net-mode", "listen", "--net-peer-key", "peer"],
    @["server", "--with-ui=1"], @["server", "--ui-port", "0"],
    @["server", "--ui-dev-dir", "a", "--ui-dev-dir", "b"],
    @["server", "--telemetry-endpoint", "a", "--telemetry-endpoint", "b"],
    @["server", "--net-peer", "1:key"], @["server", "--with-ui", "4000"],
    @["check-traces", "--trace-policy", "policy", "--trace-genesis", "genesis"],
    @["tiny-devnet", "identity", "--devnet-index", "6"], @["serve-fuzz", "--fuzz-policy", "policy"],
    @["tiny-devnet", "identity", "--devnet-index", "1", "--with-ui"], @["nonsense"]]:
  var output = parsed(peer())
  var diagnostic = ""
  assert not parseOptions(input, output, diagnostic), "CLI invariant: not parseOptions(input, output, diagnostic)"
  assert not output.valid and output.argumentCount == 0 and diagnostic.len > 0, "CLI invariant: not output.valid and output.argumentCount == 0 and diagnostic.len > 0"
for field in ["--net-port", "--net-timeout-ms"]:
  for invalid in ["0", "-1", "18446744073709551616", "١", "1000000"]:
    var input = peer()
    if field == "--net-port": input[2] = invalid
    else:
      input.add(field)
      input.add(invalid)
    var output = default(Options)
    var diagnostic = ""
    assert not parseOptions(input, output, diagnostic) and field in diagnostic, "CLI invariant: not parseOptions(input, output, diagnostic) and field in diagnostic"

proc cycle() =
  ## Retire catalog strings, repeated-value arrays and parsed owners between independent startup attempts.
  let value = parsed(peer())
  assert value.argumentCount == 8, "CLI invariant: value.argumentCount == 8"
for iteration in 0..<1000: cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "CLI invariant: before == after"
recordArcRelease("app_cli", 1000, before, after)
echo "Application CLI tests passed"
echo "ARC_RELEASE cycles=1000 unchanged"
