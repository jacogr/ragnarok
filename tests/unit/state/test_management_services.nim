# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Disabled-by-default Services wiring, independent HTTP operation and partial startup rollback.
import std/[assertions, syncio, strutils]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/management/[server, protocol]
import ../../support/[management_socket, rpc_socket]

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Fixture paths belong to this test process only.
proc main() {.raises.} =
  ## Independent management startup needs neither canonical state nor a public WS listener.
  var directory = "/tmp/ragnarok-management-services-" & $processId()
  var path = directory & "/admin.sock"
  assert mkdir(directory.toCString(), Mode(0o700)) == 0
  defer: assert rmdir(directory.toCString()) == 0 # Inner service lifetimes remove their own socket first.
  block disabled:
    var configuration = default(Options)
    assert parseCanonicalOptions(@["server", "--management-socket", path], configuration)
    var owner = default(Services)
    assert owner.start(configuration, "server")
    owner.tick(0)
    var status = default(Stat)
    assert lstat(path.toCString(), status) != 0 # Configuration alone must not expose an endpoint.
    owner.close()
  block enabled:
    var configuration = default(Options)
    assert parseCanonicalOptions(@["server", "--with-management", "--management-socket", path], configuration)
    assert configuration.rpcPort == 0 and configuration.uiPort == 0
    var owner = default(Services)
    defer: owner.close() # Services destruction is preceded by its explicit joined lifetime shutdown.
    assert owner.start(configuration, "server")
    owner.tick(0)
    let reply = managementInfo(owner.management, path)
    assert "\"stateEnabled\":false" in reply and "\"status\":\"memory\"" in reply
    assert "\"residentBytes\":null" notin reply and "\"availableBytes\":null" notin reply
    assert "\"pid\":" & $processId() in reply
    owner.close()
    owner.close() # Service close is idempotent across all independently disabled components.
    var status = default(Stat)
    assert lstat(path.toCString(), status) != 0
    assert owner.start(configuration, "server") # Reuse does not require process-global option state.
  block rollback:
    var occupied = default(ManagementServer)
    assert occupied.start(path, ManagementInfo(role: "server"))
    defer: occupied.close() # A failed competing Services startup cannot remove this listener.
    let reserved = reservation()
    discard posix.close(reserved.fd)
    var configuration = default(Options)
    assert parseCanonicalOptions(@["server", "--with-rpc", "--rpc-port", $reserved.port,
      "--with-management", "--management-socket", path], configuration)
    var owner = default(Services)
    assert not owner.start(configuration, "server")
    assertPortReleased(reserved.port) # Management refusal retires already-opened public RPC sockets.
    let reply = managementInfo(occupied, path)
    assert "\"pid\":" & $processId() in reply # The original conflicting endpoint still works.
    owner.close()

try:
  main()
except:
  quit(2) # Unexpected native/environmental failures must fail the suite.
echo "Management service tests passed"
