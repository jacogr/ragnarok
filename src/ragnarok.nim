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
import ./app/[options, cli_help, cli_commands, download_command, current_download_command,
    trace_check_command, fuzz_target, devnet_command]
import ./pvm/step
import ./version
import ./lib/logging

proc writeFailure(logger: var Logger, message: string) =
  ## Command producers have retired; drain and join stderr logging before its final CLI line.
  close(logger)
  stderr.writeLine(message)

# CLI entry point returns through all normal ARC/native teardown before process exit.
proc main(): int =
  var logger = default(Logger)
  try:
    var arguments: seq[string] = @[]
    for i in 1..paramCount(): arguments.add(paramStr(i)) # Copy process input once at the application boundary.
    var topic = ""
    if (arguments.len > 0 or not existsEnv("JAM_FUZZ")) and helpRequest(arguments, topic):
      let page = commandHelp(topic)
      if page.len == 0:
        stderr.writeLine("Unknown help topic: " & topic & "; use ragnarok --help")
        return 2
      stdout.write(page)
      return 0 # Help never starts the logger, conformance adapter or a native listener.
    let versionRequest = arguments.len == 1 and arguments[0] == "--version"
    let special = (existsEnv("JAM_FUZZ") and not versionRequest) or
      (arguments.len > 0 and arguments[0] in ["fuzz", "serve-fuzz", "serve-fuzz-preset",
          "tiny-devnet"])
    if special:
      var normalized, commandArguments: seq[string] = @[]
      var diagnostic = ""
      if not normalizeCommand(arguments, normalized, diagnostic):
        stderr.writeLine(diagnostic)
        return 2
      var withoutBackend: seq[string] = @[]
      var backend = DefaultPvmBackend
      if not extractPvmBackend(normalized, withoutBackend, backend):
        stderr.writeLine("Invalid --pvm-backend: use jit|interpreted|polkavm-interpreted|polkavm-compiled")
        return 2
      var logging = initLogPolicy()
      if not extractLoggingOptions(withoutBackend, commandArguments, logging):
        stderr.writeLine("Invalid --log-level filter")
        return 2
      let fuzzCommand = arguments.len == 0 or arguments[0] != "tiny-devnet"
      if fuzzCommand and "--log-level" notin normalized:
        # Apply the conformance environment threshold before an optional general logging filter.
        var fuzzLevel = getEnv("JAM_FUZZ_LOG_LEVEL")
        for index in 0..<max(0, normalized.len-1):
          if normalized[index] == "--fuzz-log-level": fuzzLevel = normalized[index+1]
        if fuzzLevel.len > 0 and not parseLogPolicy(fuzzLevel, logging):
          stderr.writeLine("Invalid --fuzz-log-level / JAM_FUZZ_LOG_LEVEL")
          return 2
      if not logger.start(logging): return 2
      let available = backendAvailability(backend)
      if available != StepError.None:
        writeFailure(logger, "PVM_BACKEND_UNAVAILABLE requested=" & $backend & " reason=" & $available)
        return 2
      log(logger.writer, LogTarget.Pvm, LogLevel.Info, backendSummary(backend))
      if arguments.len > 0 and arguments[0] == "tiny-devnet":
        return runDevnet(commandArguments, logger.writer, backend)
      return runFuzzTarget(commandArguments, logger.writer, backend)
    var options = default(Options)
    var diagnostic = ""
    if not parseOptions(arguments, options, diagnostic):
      stderr.writeLine(diagnostic)
      return 2 # No invalid configuration reaches a service.
    # Version inspection needs no certificates, listeners or service configuration.
    if options.argumentCount() == 1 and options.argument(1) == "--version":
      stdout.writeLine("Ragnarok " & AppVersion & " " & AppRevision)
      stdout.writeLine("Nimony " & CompilerVersion & " " & CompilerRevision)
      stdout.writeLine("Built " & BuildTimestamp)
      return 0
    if not logger.start(options.loggingPolicy): return 2
    options.attachLogWriter(logger.writer)
    let available = backendAvailability(options.pvmBackend)
    if available != StepError.None:
      writeFailure(logger, "PVM_BACKEND_UNAVAILABLE requested=" & $options.pvmBackend & " reason=" & $available)
      return 2
    log(options.logWriter, LogTarget.Pvm, LogLevel.Info, backendSummary(options.pvmBackend))
    log(options.logWriter, LogTarget.Startup, LogLevel.Info, "Ragnarok " & AppVersion & " " & AppRevision)
    if options.argumentCount() >= 1 and options.argument(1) == "check-traces":
      let outcome = runTraceChecks(options)
      if outcome.error == TraceCheckCommandError.None:
        var root = ""
        for octet in array[32, byte](outcome.finalRoot):
          root.add(toHex(int(octet), 2).toLowerAscii) # Emit the actual verified final commitment after full-map agreement.
        stdout.writeLine("TRACE_CHECK_OK checked=" & $outcome.checkedBlocks & " root=" & root)
        return 0
      writeFailure(logger, "TRACE_CHECK_FAILED " & $outcome.error & " checked=" &
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
      writeFailure(logger, "DOWNLOAD_FAILED " & $outcome.error)
      return 2 # Invalid/unavailable/exhausted downloads never imply an adopted child.
    if options.argumentCount() >= 1 and options.argument(1) == "download-current":
      let outcome = runCurrentDownloads(options)
      if outcome.requestedBlocks > 1:
        stdout.writeLine("CURRENT_DOWNLOAD_PROGRESS adopted=" & $outcome.adoptedBlocks &
          " requested=" & $outcome.requestedBlocks) # Only confirmed actual prefix progress survives joined teardown.
      if outcome.error == CurrentDownloadCommandResult.Adopted:
        stdout.writeLine("CURRENT_DOWNLOAD_ADOPTED")
        return 0 # Native streams, current execution and durable/RPC leases have already retired.
      writeFailure(logger, "CURRENT_DOWNLOAD_FAILED " & $outcome.error)
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
    writeFailure(logger, "Application setup, filesystem or CLI control failed")
    2

  finally:
    close(logger) # Every command retires its service/producer borrows before the application writer joins.

when isMainModule: quit(main()) # Never exit while a dispatcher or native callback still borrows a retiring Peer.
