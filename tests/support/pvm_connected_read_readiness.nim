# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Untimed public DOOM readiness checks using the existing exact worker gate.

import std/[assertions, syncio]
import ../../src/pvm/step
import ../../src/pvm/internal/native_pipeline

when not (NativeReadCycleEnabled and defined(pvmSharedAsyncWitness)):
  {.error: "connected readiness requires the native async witness profile".}

const
  ConnectedReadinessRefused* = when defined(pvmX86Jit): defined(pvmX86JitRefuse)
    else: defined(pvmArm64JitRefuse)
  ConnectedReadinessCalls* = when ConnectedReadinessRefused: 7 else: 5

proc holdConnectedReadiness*(runtime: NativeRuntime) =
  ## Keep the request queued for two complete public calls before allowing compilation.
  pauseNativeCompiler(runtime, true)
  armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)

proc checkWorker(runtime: NativeRuntime, phase: NativePhase, registered, completed,
    completions: int, submitted = 1'u64) =
  ## Bind the primary and, after Ready use, its one deterministically queued auxiliary.
  let observed = runtime.runtimeInfo
  if observed.phase != phase or observed.registered != registered or observed.active != 0 or
      observed.submitted != submitted or observed.completed != uint64(completed) or
      observed.completions != completions:
    # Keep a failed native packet actionable without weakening any exact counter.
    echo "CONNECTED_READINESS_WORKER_MISMATCH,", ord(observed.phase), ",", observed.registered,
      ",", observed.active, ",", observed.submitted, ",", observed.completed, ",",
          observed.completions,
      ",", ord(phase), ",", registered, ",0,", submitted, ",", completed, ",", completions
    assert false, "connected readiness: exact worker counters"

proc checkConnectedReadiness*(runtime: NativeRuntime, prepared: PreparedProgram,
    backend: PvmBackend, sample: int) =
  ## Called only after the maintained complete CPU, memory and event oracle for this public call.
  let state = preparedNativeState(prepared).value
  let observed = preparedInfo(prepared).value
  assert observed.backend == PvmBackend.Jit
  assert observed.jitBuilt and observed.jitPlatformSupported and observed.checkedFallbackEnabled
  if sample < 2:
    assert state == NativeState.Pending
    checkWorker(runtime, NativePhase.Queued, 1, 0, 0)
  else:
    when ConnectedReadinessRefused:
      let expected = if sample == 5: NativeState.Closed else: NativeState.Unavailable
      assert state == expected, "empty completion must remain unavailable across checked calls and restart"
      checkWorker(runtime, NativePhase.Idle, 0, 1, 0)
    else:
      assert state == NativeState.Ready
      checkWorker(runtime, NativePhase.Queued, 2, 1, 0, submitted = 2)
  if ConnectedReadinessRefused or sample < 2:
    assert backend == PvmBackend.Interpreted
    assert observed.nativeFragments == 0 and observed.nativeCodeBytes == 0
    assert observed.nativeCalls == 0 and observed.nativeOperations == 0
    assert observed.nativeBranchCalls == 0 and observed.nativeHeaderCalls == 0
  else:
    assert backend == PvmBackend.Jit and observed.nativeFragments == 1
    let extent = when defined(pvmX86Jit): 3350'u64 else: 2696'u64
    let resident = uint64(sample - 1)
    assert observed.nativeCodeBytes == extent
    assert observed.nativeCalls == 651'u64 * resident
    assert observed.nativeOperations == 10865293'u64 * resident
    assert observed.nativeBranchCalls == 650'u64 * resident
    assert observed.nativeHeaderCalls == 650'u64 * resident
  let worker = runtime.runtimeInfo
  echo "CONNECTED_READINESS_CALL,", sample, ",", ord(state), ",", ord(backend),
    ",", worker.submitted, ",", worker.completed, ",", worker.registered, ",", worker.completions,
    ",", observed.nativeFragments, ",", observed.nativeCodeBytes, ",", observed.nativeCalls,
    ",", observed.nativeOperations, ",", observed.nativeBranchCalls, ",", observed.nativeHeaderCalls

  if sample == 1:
    # Work is held until after the same owner has completed a second checked call.
    pauseNativeCompiler(runtime, false)
    let image = waitNativeCompilerGate(runtime)
    assert image.point == NativeCompilerPoint.BeforePublish and image.kind ==
        NativeKind.ConnectedReadCycle
    assert image.hasImage == (not ConnectedReadinessRefused)
    assert image.slot == 0 and image.generation == 1 and image.ticket == 1 and image.epoch == 1
    echo "CONNECTED_READINESS_GATE,ConnectedReadCycle,", ord(image.hasImage), ",", image.slot,
      ",", image.generation, ",", image.ticket, ",", image.epoch
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    assert preparedNativeState(prepared).value == NativeState.Pending
    checkWorker(runtime, NativePhase.Done, 1, 1, 1)
    echo "CONNECTED_READINESS_PARKED,1,1,1,1"
    # Keep the auxiliary offered by later Ready calls queued, preserving primary-only work.
    # Native auxiliary execution and ownership have their own complete arena witnesses.
    pauseNativeCompiler(runtime, true)
  when ConnectedReadinessRefused:
    if sample == 4:
      # A surviving refused owner holds no slot and keeps its checked behavior after close.
      assert close(runtime)
      assert preparedNativeState(prepared).value == NativeState.Closed
      checkWorker(runtime, NativePhase.Idle, 0, 1, 0)
    elif sample == 5:
      # An explicit empty restart cannot turn the existing unavailable epoch into a new request.
      try:
        assert start(runtime)
      except:
        assert false, "connected readiness: runtime restart failed"
      assert preparedNativeState(prepared).value == NativeState.Unavailable
      checkWorker(runtime, NativePhase.Idle, 0, 1, 0)

proc finishConnectedReadiness*(runtime: NativeRuntime) =
  ## The caller drops the prepared owner before proving final native credit retirement.
  let submitted = if ConnectedReadinessRefused: 1'u64 else: 2'u64
  checkWorker(runtime, NativePhase.Idle, 0, 1, 0, submitted)
  pauseNativeCompiler(runtime, false)
  assert close(runtime)
  checkWorker(runtime, NativePhase.Idle, 0, 1, 0, submitted)
  echo "CONNECTED_READINESS_DONE,", ord(ConnectedReadinessRefused), ",", ConnectedReadinessCalls,
    ",", submitted, ",1,0"
