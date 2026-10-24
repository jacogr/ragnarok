# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Consolidated application entry point for networking, telemetry, RPC and the embedded UI.
## Every run returns through native/ARC cleanup before exit.
##
## Parses one explicit configuration and selects peer/mesh workloads, bounded selftests or offline trace checking.
## This is the production build and E2E entry point; full node execution remains future work.

import std/[os, strutils, monotimes, times, syncio, envvars]
import std/posix/posix
import ./quic/[session, transport, integration, offload]
import ./app/[options, download_command, current_download_command, trace_check_command]
import ./version

# CLI entry point returns through all normal ARC/native teardown before process exit.
proc main(): int =
  try:
    var arguments: seq[string] = @[]
    for i in 1..paramCount(): arguments.add(paramStr(i)) # Copy process input once at the application boundary.
    var options = default(Options)
    if not parseOptions(arguments, options): return 2 # No invalid configuration reaches a service.
    # Version inspection needs no certificates, listeners or service configuration.
    if options.argumentCount() == 1 and options.argument(1) == "--version":
      stdout.writeLine("Ragnarok " & AppVersion & " " & AppRevision)
      stdout.writeLine("Nimony " & CompilerVersion & " " & CompilerRevision)
      stdout.writeLine("Built " & BuildTimestamp)
      return 0
    if options.argumentCount() == 1 and options.argument(1) == "--help":
      stdout.writeLine("Usage: ragnarok server|client PORT CERT KEY PEER ALPN TIMEOUT [MODE] [OPTIONS]")
      stdout.writeLine("       ragnarok mesh LOCAL_PORT REMOTE_PORT CERT KEY LOCAL_KEY PEER_KEY ALPN GATE [OPTIONS]")
      stdout.writeLine("       ragnarok download PORT CERT KEY PEER ALPN TIMEOUT POLICY [PORT PEER ...] [OPTIONS]")
      stdout.writeLine("       ragnarok download-current PORT CERT KEY PEER ALPN TIMEOUT CURRENT_POLICY [PORT PEER ...] [OPTIONS]")
      stdout.writeLine("         download-current requires ragnarok-current-download-policy-v1; discovery permission must match the requested mode.")
      stdout.writeLine("       ragnarok check-traces CURRENT_POLICY GENESIS TRACE [TRACE ...] --with-state --chain FILE [STATE_BUDGETS]")
      stdout.writeLine("         check-traces optionally compares --trace-observations DIR/step-0000.bin (published RawState).")
      stdout.writeLine("       ragnarok --version | --help")
      stdout.writeLine("Options: --with-telemetry --telemetry HOST:PORT --chain FILE")
      stdout.writeLine("         --with-rpc --rpc-port NUMBER --with-ui --ui-port NUMBER --dev-ui-dir DIRECTORY")
      stdout.writeLine("         --with-management --management-socket /PRIVATE_DIRECTORY/admin.sock (local HTTP; disabled by default)")
      stdout.writeLine("         --with-state --chain FILE [--state-writes COUNT] [--state-write-bytes BYTES]")
      stdout.writeLine("         State mutation defaults: 1000 writes, 100000 value bytes per batch.")
      stdout.writeLine("         --state-storage memory|disk --state-db PATH (disk requires --with-state)")
      stdout.writeLine("         --state-layout journal|managed (disk only; default journal)")
      stdout.writeLine("         --state-compact-bytes BYTES (managed only; default 67108864, max 134217728; 0 disables automatic maintenance)")
      stdout.writeLine("         --state-migrate-from LEGACY_PATH (managed only; requires a separate new --state-db destination)")
      stdout.writeLine("         --state-checkpoint FILE --state-trust FILE --state-header FILE --state-checkpoint-bytes BYTES")
      stdout.writeLine("         Checkpoint imports require independent trusted identity/header; restart retains one unfinalized head.")
      stdout.writeLine("         --download-ancestor FILE (repeat newest-first; download commands only, maximum 64)")
      stdout.writeLine("         --download-local-ancestors (download commands only; prepend all retained local parents)")
      stdout.writeLine("         --download-remote-ancestors COUNT (download commands only; fetch up to 1..64 older parents)")
      stdout.writeLine("         --download-discover-ancestors COUNT (download commands only; fetch on demand, 1..64 headers per run)")
      stdout.writeLine("         --download-blocks COUNT (download commands only, default 1, range 1..64)")
      stdout.writeLine("State limits are unsigned budgets; supplied complete state is structurally checked.")
      return 0
    if options.argumentCount() >= 1 and options.argument(1) == "check-traces":
      let outcome = runTraceChecks(options)
      if outcome.error == TraceCheckCommandError.None:
        var root = ""
        for octet in array[32, byte](outcome.finalRoot):
          root.add(toHex(int(octet), 2).toLowerAscii) # Emit the actual verified final commitment after full-map agreement.
        stdout.writeLine("TRACE_CHECK_OK checked=" & $outcome.checkedBlocks & " root=" & root)
        return 0
      stderr.writeLine("TRACE_CHECK_FAILED " & $outcome.error & " checked=" &
          $outcome.checkedBlocks & " " & outcome.detail)
      return 2 # The private ephemeral chain and every owned file/candidate retire before command exit.
    if options.argumentCount() >= 1 and options.argument(1) == "download":
      let outcome = runDownloads(options)
      if outcome.requestedBlocks > 1:
        stdout.writeLine("DOWNLOAD_PROGRESS adopted=" & $outcome.adoptedBlocks & " requested=" &
            $outcome.requestedBlocks)
      if outcome.error == DownloadCommandResult.Adopted:
        stdout.writeLine("DOWNLOAD_ADOPTED")
        return 0 # Command owners have already retired callbacks and canonical Services.
      stderr.writeLine("DOWNLOAD_FAILED " & $outcome.error)
      return 2 # Invalid/unavailable/exhausted downloads never imply an adopted child.
    if options.argumentCount() >= 1 and options.argument(1) == "download-current":
      let outcome = runCurrentDownloads(options)
      if outcome.requestedBlocks > 1:
        stdout.writeLine("CURRENT_DOWNLOAD_PROGRESS adopted=" & $outcome.adoptedBlocks &
          " requested=" & $outcome.requestedBlocks) # Only confirmed actual prefix progress survives joined teardown.
      if outcome.error == CurrentDownloadCommandResult.Adopted:
        stdout.writeLine("CURRENT_DOWNLOAD_ADOPTED")
        return 0 # Native streams, current execution and durable/RPC leases have already retired.
      stderr.writeLine("CURRENT_DOWNLOAD_FAILED " & $outcome.error)
      return 2 # A refused/exhausted current run does not imply successful adoption.
    # Retained dual-role peers have a separate bounded CLI and preserve normal proof workloads.
    if options.argumentCount() >= 1 and options.argument(1) == "mesh":
      let baseline = getOccupiedMem()
      if not runMesh(options): return 2 # Both engines and their borrowed dispatcher registrations have already retired.
      let retained = getOccupiedMem()
      progress "MESH_CLEAN ", baseline, " ", retained
      return (if retained <= baseline + 65536: 0 else: 2) # Fixed ARC bookkeeping is bounded after complete cleanup.
    if options.argumentCount() == 1 and options.argument(1) == "--mesh-selftest": meshSelfTest(); return 0
    # The composition selftest needs only codec/crypto, with no TLS session or filesystem fixture.
    if options.argumentCount() == 1 and options.argument(1) == "--integration-selftest":
      if not IntegrationEnabled: return 2
      integrationSelfTest()
      return 0
    # Completion-capacity checks create workers but no native transport.
    if options.argumentCount() == 1 and options.argument(1) == "--offload-selftest":
      if not OffloadEnabled: return 2
      offloadSelfTest()
      return 0
    # Held shutdown owns threads but has not entered a Rust call or started networking.
    if options.argumentCount() == 1 and options.argument(1) == "--offload-held-shutdown":
      if not OffloadEnabled: return 2
      offloadHeldShutdownTest()
      return 0
    # Parser tests create no native transport or socket.
    if options.argumentCount() == 1 and options.argument(1) == "--selftest":
      peerSelfTest()
      return 0
    # Probe the real selector backend independently of TLS setup.
    if options.argumentCount() == 1 and options.argument(1) == "--io-selftest":
      ioSelfTest()
      return 0
    if options.argumentCount() == 8 and options.argument(8) == "soak":
      # Keep the same process and ARC allocator across all independently owned endpoint sessions.
      let rounds = parseInt(getEnv("RAGNAROK_SOAK_ROUNDS"))
      let gate = getEnv("RAGNAROK_SOAK_GATE")
      # Invalid controls cannot park the process indefinitely.
      if rounds < 1 or rounds > 1000 or gate.len == 0:
        return 2
      for iteration in 0..rounds:
        let control = gate / (options.argument(1) & "-" & $iteration)
        let started = getMonoTime()
        # The harness samples only after complete cleanup, then releases the next session explicitly.
        while not fileExists(control):
          if (getMonoTime() - started).inSeconds > 15: return 2 # Bound a dead/missing harness.
          var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 10_000_000)
          var remaining = default(Timespec)
          discard nanosleep(requested, remaining) # Interrupts return to the bounded outer deadline; no endpoint is live.
        if iteration == rounds: break # Hold the final idle sample until the harness permits normal exit.
        if not runPeer(options): return 2 # Deferred dispatcher/native cleanup finishes before failure returns.
        progress "ALLOC_BYTES ", getOccupiedMem(), " RESERVED_BYTES ", getTotalMem()
        progress "SESSION_DONE ", iteration
    elif options.argumentCount() == 8 and options.argument(8) in ["service", "integration",
        "overload", "offload"]:
      # Final native callbacks and ARC release complete before observing the process-level application baseline.
      let baseline = getOccupiedMem()
      if not runPeer(options): return 2
      progress "SERVICE_CLEAN ", baseline, " ", getOccupiedMem()
      if getOccupiedMem() > baseline + 65536: return 2 # Permit fixed runtime bookkeeping, not retained stream storage.
    elif not runPeer(options):
      return 2 # The one-shot rejection suite must distinguish failed exchange from successful authentication.
    0
  except:
    # Setup/OS/control errors become bounded process failures after all native owners have retired.
    stderr.writeLine("Application setup, filesystem or CLI control failed")
    2

when isMainModule: quit(main()) # Never exit while a dispatcher or native callback still borrows a retiring Peer.
