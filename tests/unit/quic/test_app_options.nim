# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate independent application configurations without process arguments, sockets or native services.
## The parser owns copied positions, commits only valid results, and requires explicit enable flags.

import std/[assertions, syncio]
import ../../../src/app/options
import ../../../src/codec/bounded

# An absent enable flag leaves all services disabled, regardless of endpoint/directory configuration.
var disabled = default(Options)
assert not disabled.valid()
assert parseOptions(@["server", "8000", "--rpc-port", "1234", "--ui-port", "4321",
    "--dev-ui-dir", "missing", "--telemetry", "invalid"], disabled)
assert disabled.valid() and disabled.argumentCount() == 2
assert disabled.argument(1) == "server" and disabled.argument(2) == "8000"
assert not disabled.telemetryEnabled() and disabled.rpcPort() == 0 and disabled.uiPort() == 0

# UI implies RPC, with defaults or independently configured ports in any trailing order.
var ui = default(Options)
assert parseOptions(@["server", "--with-ui"], ui)
assert ui.uiPort() == 8888 and ui.rpcPort() == 19800
var custom = default(Options)
assert parseOptions(@["mesh", "--ui-port", "9001", "--with-ui", "--with-rpc", "--rpc-port", "9002",
    "--chain", "chain.json", "--with-telemetry", "--telemetry", "127.0.0.1:9003"], custom)
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
  assert parseOptions(@["server", "--with-ui"], ui)
  assert not parseOptions(arguments, ui)
  assert not ui.valid() and ui.argumentCount() == 0
  assert ui.rpcPort() == 0 and ui.uiPort() == 0 and not ui.telemetryEnabled()

# Copying caller input cannot mutate the private stored command or invalidate validated ports.
var original = @["client", "--with-rpc", "--rpc-port", "65535"]
var owned = default(Options)
assert parseOptions(original, owned)
original[0] = "changed"
assert owned.argument(1) == "client" and owned.rpcPort() == 65535

# Canonical state is an independent activation with two mandatory exact unsigned budgets.
var state = default(Options)
assert not state.stateEnabled
assert parseOptions(@["server", "--with-state", "--chain", "seed.json",
  "--state-writes", "18446744073709551615", "--state-write-bytes", "0"], state)
assert state.stateEnabled and state.rpcPort == 0 and state.uiPort == 0 and
    not state.telemetryEnabled
assert uint64(state.stateWrites) == high(uint64) and uint64(state.stateWriteBytes) == 0
let alias = state
assert parseOptions(@["mesh", "--state-write-bytes", "18446744073709551615", "--chain",
  "other.json",
  "--state-writes", "00000000000000000001", "--with-state", "--with-ui"], state)
assert state.stateEnabled and uint64(state.stateWrites) == 1
assert uint64(state.stateWriteBytes) == high(uint64) and state.rpcPort == 19800
assert alias.chainPath == "seed.json" and uint64(alias.stateWrites) == high(uint64)

# Neither malformed nor inactive policies retain old flags, old positions or partially parsed budget values.
for arguments in [@["server", "--with-state"],
    @["server", "--with-state", "--chain", "seed.json"],
    @["server", "--with-state", "--chain", "seed.json", "--state-writes", "1"],
    @["server", "--with-state", "--state-writes", "1", "--state-write-bytes", "1"],
    @["server", "--with-state", "--chain", "seed.json", "--state-write-bytes", "1"],
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
  assert not parseOptions(arguments, state)
  assert not state.valid and not state.stateEnabled and state.argumentCount == 0
  assert state.chainPath.len == 0
for invalid in ["", "-1", "+1", " 1", "1 ", "1.0", "1e2", "0x10", "١", "18446744073709551616",
    "99999999999999999999", "000000000000000000000"]:
  for name in ["--state-writes", "--state-write-bytes"]:
    var arguments = @["client", "--with-state", "--chain", "seed.json"]
    for field in ["--state-writes", "--state-write-bytes"]:
      arguments.add(field)
      arguments.add(if field == name: invalid else: "1") # Exercise overflow and syntax independently in each field.
    assert not parseOptions(arguments, state)
    assert not state.valid and not state.stateEnabled
for command in ["server", "client", "mesh"]:
  assert parseOptions(@[command, "--with-state", "--chain", "seed.json", "--state-writes", "0",
    "--state-write-bytes", "00000000000000000000"], state)
  assert state.stateEnabled and uint64(state.stateWrites) == 0 and uint64(state.stateWriteBytes) == 0
assert parseOptions(@["server"], state)
assert not state.stateEnabled # A later legacy parse cannot inherit an earlier canonical policy.

echo "Application options tests passed"
