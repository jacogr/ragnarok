# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate independent application configurations without process arguments, sockets or native services.
## The parser owns copied positions, commits only valid results, and requires explicit enable flags.

import std/[assertions, syncio]
import ../../../src/app/options

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

echo "Application options tests passed"
