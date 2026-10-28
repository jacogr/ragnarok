# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional MCP startup, configured/canonical reads, exclusion, rollback and restart through Services.
import std/[assertions, syncio, strutils]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/mcp/server
import ../../../src/rpc/server as rpc
import ../../support/rpc_socket as sockets
import ../../support/[mcp_context, mcp_socket]

proc main() {.raises.} =
  ## Disabled settings and failed startup never retain a port or canonical graph lease.
  writeFile("mcp-chain.json", mcpChainText())
  let reserved = sockets.reservation()
  let port = reserved.port
  discard posix.close(reserved.fd)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--mcp-port", $port], options)
  var owner = default(Services)
  assert owner.start(options, "server")
  assert not owner.mcp.enabled
  owner.close()
  for stateful in [false, true]:
    # Both configured-only and canonical modes share the exact original chain identity.
    var arguments = @["server", "--with-mcp", "--mcp-port", $port,
      "--chain", "mcp-chain.json"]
    if stateful: arguments.add("--with-state")
    assert parseCanonicalOptions(arguments, options)
    assert options.rpcPort == 0 and options.managementSocket == ""
    assert owner.start(options, "server")
    assert owner.mcp.enabled
    let status = mcpTool(owner, port, "get_chain_status")
    assert "200 OK" in status and "genesisHash" in status and "\"isError\":false" in status
    assert "\"finalizedBlock\":null" in status
    let parameters = mcpTool(owner, port, "get_parameters")
    assert "18446744073709551615" in parameters and "\"isError\":false" in parameters
    let lease = owner.rpc.pauseChain()
    assert lease != nil
    let busy = mcpTool(owner, port, "get_chain_status")
    assert "retryable" in busy and "\"isError\":true" in busy
    assert owner.rpc.resumeChain(lease)
    assert "\"isError\":false" in mcpTool(owner, port, "get_chain_status")
    owner.close()
    owner.close()
    var restart = default(McpServer)
    assert restart.start(port) # Rebind even while drained HTTP connections retain TCP TIME_WAIT.
    restart.close()
  block rollback:
    # A failed MCP bind must roll back an already opened RPC listener without closing its competitor.
    var occupied = default(McpServer)
    assert occupied.start(port)
    let other = sockets.reservation()
    discard posix.close(other.fd)
    assert parseCanonicalOptions(@["server", "--with-mcp", "--mcp-port", $port,
      "--with-rpc", "--rpc-port", $other.port], options)
    assert not owner.start(options, "server")
    sockets.assertPortReleased(other.port)
    occupied.close()
  owner.close()

try:
  main()
except:
  quit(2) # Unexpected filesystem/startup exceptions are failed verification.
echo "MCP services passed"
