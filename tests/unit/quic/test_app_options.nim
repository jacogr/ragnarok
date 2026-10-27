# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate independent application configurations without process arguments, sockets or native services.
## The parser owns copied positions, commits only valid results, and requires explicit enable flags.

import std/[assertions, syncio]
import ../../../src/app/options
import ../../../src/lib/logging
import ../../../src/codec/bounded

# An absent enable flag leaves all services disabled, regardless of endpoint/directory configuration.
var disabled = default(Options)
assert not disabled.valid()
assert parseCanonicalOptions(@["server", "8000", "--rpc-port", "1234", "--ui-port", "4321",
    "--dev-ui-dir", "missing", "--telemetry", "invalid"], disabled)
assert disabled.valid() and disabled.argumentCount() == 2
assert disabled.argument(1) == "server" and disabled.argument(2) == "8000"
assert not disabled.telemetryEnabled() and disabled.rpcPort() == 0 and disabled.uiPort() == 0

# UI implies RPC, with defaults or independently configured ports in any trailing order.
var ui = default(Options)
assert parseCanonicalOptions(@["server", "--with-ui"], ui)
assert ui.uiPort() == 8888 and ui.rpcPort() == 19800
var custom = default(Options)
assert parseCanonicalOptions(@["mesh", "--ui-port", "9001", "--with-ui", "--with-rpc", "--rpc-port",
    "9002", "--chain", "chain.json", "--with-telemetry", "--telemetry", "127.0.0.1:9003"], custom)
assert custom.uiPort() == 9001 and custom.rpcPort() == 9002 and custom.telemetryEnabled()
assert custom.chainPath() == "chain.json" and custom.telemetryEndpoint() == "127.0.0.1:9003"
assert ui.rpcPort() == 19800 and not ui.telemetryEnabled() # Independent invocations never share mutable state.

# Malformed parses clear a previously valid output; neither partial flags nor old values escape.
for arguments in [@["server", "--with-ui", "--ui-port", "19800"],
    @["server", "--with-ui", "--with-ui"], @["server", "--rpc-port", "65536"],
    @["server", "--rpc-port", "0"], @["server", "--rpc-port", "no"],
    @["server", "--with-rpc", "--unknown"], @["server", "--with-telemetry"],
    @["server", "--with-telemetry", "--telemetry", "127.0.0.1:1"],
    @["server", "--chain", "chain.json"], @["server", "--dev-ui-dir", "--with-ui"],
    @["server", "--rpc-port"], @["--selftest", "--with-ui"], @["--with-rpc"]]:
  assert parseCanonicalOptions(@["server", "--with-ui"], ui)
  assert not parseCanonicalOptions(arguments, ui)
  assert not ui.valid() and ui.argumentCount() == 0
  assert ui.rpcPort() == 0 and ui.uiPort() == 0 and not ui.telemetryEnabled()

# Copying caller input cannot mutate the private stored command or invalidate validated ports.
var original = @["client", "--with-rpc", "--rpc-port", "65535"]
var owned = default(Options)
assert parseCanonicalOptions(original, owned)
original[0] = "changed"
assert owned.argument(1) == "client" and owned.rpcPort() == 65535

# Canonical state is an independent activation with independently defaulted or overridden unsigned budgets.
var state = default(Options)
assert not state.stateEnabled
assert parseCanonicalOptions(@["server", "--with-state", "--chain", "seed.json",
  "--state-writes", "18446744073709551615", "--state-write-bytes", "0"], state)
assert state.stateEnabled and state.rpcPort == 0 and state.uiPort == 0 and
    not state.telemetryEnabled
assert uint64(state.stateWrites) == high(uint64) and uint64(state.stateWriteBytes) == 0
let alias = state
assert parseCanonicalOptions(@["mesh", "--state-write-bytes", "18446744073709551615", "--chain",
  "other.json",
  "--state-writes", "00000000000000000001", "--with-state", "--with-ui"], state)
assert state.stateEnabled and uint64(state.stateWrites) == 1
assert uint64(state.stateWriteBytes) == high(uint64) and state.rpcPort == 19800
assert alias.chainPath == "seed.json" and uint64(alias.stateWrites) == high(uint64)

# Omitted ceilings default independently; explicit zero and later parses never inherit prior values.
for command in ["server", "client", "mesh", "download"]:
  let base = @[command, "--with-state", "--chain", "seed.json"]
  assert parseCanonicalOptions(base, state)
  assert uint64(state.stateWrites) == 1000 and uint64(state.stateWriteBytes) == 100000
  var countOnly = base
  countOnly.add("--state-writes"); countOnly.add("0")
  assert parseCanonicalOptions(countOnly, state)
  assert uint64(state.stateWrites) == 0 and uint64(state.stateWriteBytes) == 100000
  var bytesOnly = base
  bytesOnly.add("--state-write-bytes"); bytesOnly.add("0")
  assert parseCanonicalOptions(bytesOnly, state)
  assert uint64(state.stateWrites) == 1000 and uint64(state.stateWriteBytes) == 0
  assert parseCanonicalOptions(base, state)
  assert uint64(state.stateWrites) == 1000 and uint64(state.stateWriteBytes) == 100000

# Neither malformed nor inactive policies retain old flags, old positions or partially parsed budget values.
for arguments in [@["server", "--with-state"],
    @["server", "--with-state", "--state-writes", "1", "--state-write-bytes", "1"],
    @["server", "--state-writes", "1"], @["server", "--state-write-bytes", "1"],
    @["server", "--with-state", "--with-state"],
    @["server", "--with-state", "--chain", "seed.json", "--state-writes", "0",
        "--state-write-bytes", "0", "--state-writes", "0"],
    @["server", "--with-state", "--chain", "seed.json", "--state-writes", "0",
        "--state-write-bytes", "0", "--state-write-bytes", "0"],
    @["--selftest", "--with-state", "--chain", "seed.json", "--state-writes", "0",
        "--state-write-bytes", "0"],
    @["--version", "--with-state", "--chain", "seed.json", "--state-writes", "0",
        "--state-write-bytes", "0"]]:
  assert not parseCanonicalOptions(arguments, state)
  assert not state.valid and not state.stateEnabled and state.argumentCount == 0
  assert state.chainPath.len == 0
for invalid in ["", "-1", "+1", " 1", "1 ", "1.0", "1e2", "0x10", "١", "18446744073709551616",
    "99999999999999999999", "000000000000000000000"]:
  for name in ["--state-writes", "--state-write-bytes"]:
    var arguments = @["client", "--with-state", "--chain", "seed.json"]
    for field in ["--state-writes", "--state-write-bytes"]:
      arguments.add(field)
      arguments.add(if field == name: invalid else: "1") # Exercise overflow and syntax independently in each field.
    assert not parseCanonicalOptions(arguments, state)
    assert not state.valid and not state.stateEnabled
for command in ["server", "client", "mesh"]:
  assert parseCanonicalOptions(@[command, "--with-state", "--chain", "seed.json", "--state-writes", "0",
    "--state-write-bytes", "00000000000000000000"], state)
  assert state.stateEnabled and uint64(state.stateWrites) == 0 and uint64(state.stateWriteBytes) == 0
assert parseCanonicalOptions(@["server"], state)
assert not state.stateEnabled # A later legacy parse cannot inherit an earlier canonical policy.

# Management is independently explicit: neither endpoint configuration nor WS/UI/state activates it.
var management = default(Options)
assert management.managementSocket == ""
for arguments in [@["server"], @["server", "--with-ui"], @["server", "--with-rpc"],
    @["server", "--management-socket", "/private/admin.sock"]]:
  assert parseCanonicalOptions(arguments, management) and management.managementSocket == ""
assert parseCanonicalOptions(@["server", "--with-management", "--management-socket",
    "/private/admin.sock"], management)
assert management.managementSocket == "/private/admin.sock" and management.rpcPort == 0 and
    management.uiPort == 0
for arguments in [@["server", "--with-management"],
    @["server", "--with-management", "--management-socket", "relative.sock"],
    @["server", "--with-management", "--management-socket", "/private/"],
    @["server", "--with-management", "--management-socket", "/private/a\0b"],
    @["server", "--with-management", "--with-management", "--management-socket",
        "/private/admin.sock"],
    @["--version", "--with-management", "--management-socket", "/private/admin.sock"]]:
  assert not parseCanonicalOptions(arguments, management) and management.managementSocket == ""

# Logging policies are copied/validated before services start; duplicates and partial overrides refuse atomically.
var logs = default(Options)
assert parseCanonicalOptions(@["--help"], logs)
assert logs.loggingPolicy.threshold(LogTarget.Pvm) == LogLevel.Info
assert parseCanonicalOptions(@["--help", "--log-level", "warn,pvm=trace,network=off"], logs)
assert logs.loggingPolicy.threshold(LogTarget.Pvm) == LogLevel.Trace
assert logs.loggingPolicy.threshold(LogTarget.Network) == LogLevel.Off
assert logs.loggingPolicy.threshold(LogTarget.Rpc) == LogLevel.Warn
for arguments in [@["--help", "--log-level"], @["--help", "--log-level", ""],
    @["--help", "--log-level", "BAD"], @["--help", "--log-level", "pvm=debug,pvm=info"],
    @["--help", "--log-level", "info", "--log-level", "trace"]]:
  assert not parseCanonicalOptions(arguments, logs) and not logs.valid
# Offline trace commands admit the shared diagnostic filter without weakening their service whitelist.
assert parseCanonicalOptions(@["check-traces", "policy", "genesis", "trace", "--with-state", "--chain",
  "chain.json", "--log-level", "off"], logs)
assert logs.loggingPolicy.threshold(LogTarget.Pvm) == LogLevel.Off
var stripped: seq[string] = @[]
var filter = default(LogPolicy)
assert extractLoggingOptions(@["tiny-devnet", "identity", "0", "--log-level", "off"], stripped, filter)
assert stripped == @["tiny-devnet", "identity", "0"]
assert filter.threshold(LogTarget.Startup) == LogLevel.Off
assert not extractLoggingOptions(@["--log-level", "off", "--log-level", "info"], stripped, filter)

echo "Application options tests passed"
