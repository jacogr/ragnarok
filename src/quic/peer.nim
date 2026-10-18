## Bounded CLI controls for private peer sessions; every run returns through native/ARC cleanup before exit.
import std/[os, strutils, monotimes, times, syncio, envvars]
import std/posix/posix
import ./[session, transport, integration, offload]
import ../telemetry/options

# CLI entry point returns through all normal ARC/native teardown before process exit.
proc main(): int =
  try:
    if not validTelemetryOption(): return 2 # Malformed optional syntax must not become a fixture attack mode.
    # Only network commands accept telemetry; each command validates its own positional shape.
    if (requested() or rpcPort() != 0) and (peerParamCount() < 1 or paramStr(1) notin ["server",
        "client", "mesh"]): return 2
    # Retained dual-role peers have a separate bounded CLI and preserve normal proof workloads.
    if peerParamCount() >= 1 and paramStr(1) == "mesh":
      let baseline = getOccupiedMem()
      if not runMesh(): return 2 # Both engines and their borrowed dispatcher registrations have already retired.
      let retained = getOccupiedMem()
      progress "MESH_CLEAN ", baseline, " ", retained
      return (if retained <= baseline + 65536: 0 else: 2) # Fixed ARC bookkeeping is bounded after complete cleanup.
    if peerParamCount() == 1 and paramStr(1) == "--mesh-selftest": meshSelfTest(); return 0
    # The composition selftest needs only codec/crypto, with no TLS session or filesystem fixture.
    if peerParamCount() == 1 and paramStr(1) == "--integration-selftest":
      if not IntegrationEnabled: return 2
      integrationSelfTest()
      return 0
    # Completion-capacity checks create workers but no native transport.
    if peerParamCount() == 1 and paramStr(1) == "--offload-selftest":
      if not OffloadEnabled: return 2
      offloadSelfTest()
      return 0
    # Held shutdown owns threads but has not entered a Rust call or started networking.
    if peerParamCount() == 1 and paramStr(1) == "--offload-held-shutdown":
      if not OffloadEnabled: return 2
      offloadHeldShutdownTest()
      return 0
    # Parser tests create no native transport or socket.
    if peerParamCount() == 1 and paramStr(1) == "--selftest":
      peerSelfTest()
      return 0
    # Probe the real selector backend independently of TLS setup.
    if peerParamCount() == 1 and paramStr(1) == "--io-selftest":
      ioSelfTest()
      return 0
    if peerParamCount() == 8 and paramStr(8) == "soak":
      # Keep the same process and ARC allocator across all independently owned endpoint sessions.
      let rounds = parseInt(getEnv("RAGNAROK_SOAK_ROUNDS"))
      let gate = getEnv("RAGNAROK_SOAK_GATE")
      # Invalid controls cannot park the process indefinitely.
      if rounds < 1 or rounds > 1000 or gate.len == 0:
        return 2
      for iteration in 0..rounds:
        let control = gate / (paramStr(1) & "-" & $iteration)
        let started = getMonoTime()
        # The harness samples only after complete cleanup, then releases the next session explicitly.
        while not fileExists(control):
          if (getMonoTime() - started).inSeconds > 15: return 2 # Bound a dead/missing harness.
          var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 10_000_000)
          var remaining = default(Timespec)
          discard nanosleep(requested, remaining) # Interrupts return to the bounded outer deadline; no endpoint is live.
        if iteration == rounds: break # Hold the final idle sample until the harness permits normal exit.
        if not runPeer(): return 2 # Deferred dispatcher/native cleanup finishes before failure returns.
        progress "ALLOC_BYTES ", getOccupiedMem(), " RESERVED_BYTES ", getTotalMem()
        progress "SESSION_DONE ", iteration
    elif peerParamCount() == 8 and paramStr(8) in ["service", "integration", "overload", "offload"]:
      # Final native callbacks and ARC release complete before observing the process-level application baseline.
      let baseline = getOccupiedMem()
      if not runPeer(): return 2
      progress "SERVICE_CLEAN ", baseline, " ", getOccupiedMem()
      if getOccupiedMem() > baseline + 65536: return 2 # Permit fixed runtime bookkeeping, not retained stream storage.
    elif not runPeer():
      return 2 # The one-shot rejection suite must distinguish failed exchange from successful authentication.
    0
  except:
    # Setup/OS/control errors become bounded process failures after all native owners have retired.
    stderr.writeLine("Peer setup, filesystem or CLI control failed")
    2

quit(main()) # Never exit while a dispatcher or native callback still borrows a retiring Peer.
