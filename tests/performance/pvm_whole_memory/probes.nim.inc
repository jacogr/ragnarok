# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Compile-only correctness hooks force publication/COW through an actual copied writer alias during a live lease.
when defined(pvmWholeNativeLeaseControls):
  type
    LeaseProbe* {.pure.} = enum ## Explicit correctness-only disruptions; never compiled into timing callbacks.
      ReadThenCow, StoreThenSeal, ReadThenUnchangedSeal, StoreThenOverlap, Saturated,
      ReadThenStaticCow, ReadThenFailedStore, ReadThenSaturatingCow
    ProbeState = ref object ## The wrapper retains this acyclic owner throughout its borrowed context pointer.
      mode: LeaseProbe
      alias: ScalarMemoryWriter
      replacement: uint64
      fired: bool
      saved: Memory

  proc runLeaseProbe(context: ptr Invocation, address, width: uint64, storing: bool) =
    ## Deliberately leave descriptors stale; only the generated live-generation guard can revoke their authority.
    if context.testProbe == nil: return
    let probe {.cursor.} = cast[ProbeState](context.testProbe)
    if probe.fired: return
    if (probe.mode in [LeaseProbe.ReadThenCow, LeaseProbe.ReadThenUnchangedSeal,
        LeaseProbe.ReadThenStaticCow, LeaseProbe.ReadThenFailedStore, LeaseProbe.ReadThenSaturatingCow] and
            storing) or
        (probe.mode in [LeaseProbe.StoreThenSeal, LeaseProbe.StoreThenOverlap] and
            not storing): return
    probe.fired = true
    case probe.mode
    of LeaseProbe.ReadThenCow, LeaseProbe.StoreThenOverlap, LeaseProbe.ReadThenSaturatingCow:
      if probe.mode != LeaseProbe.StoreThenOverlap: assert context.readPointer != nil
      let changed = store(probe.alias, MemoryAddress(address), AccessWidth(byte(width)),
          RegisterValue(probe.replacement))
      assert changed.error == MachineError.None
    of LeaseProbe.ReadThenStaticCow:
      # Every public static-width overload must revoke the live read lease before its original COW path.
      assert context.readPointer != nil
      let changed = case width
        of 1: store[1](probe.alias, MemoryAddress(address), RegisterValue(probe.replacement))
        of 2: store[2](probe.alias, MemoryAddress(address), RegisterValue(probe.replacement))
        of 4: store[4](probe.alias, MemoryAddress(address), RegisterValue(probe.replacement))
        else: store[8](probe.alias, MemoryAddress(address), RegisterValue(probe.replacement))
      assert changed.error == MachineError.None
    of LeaseProbe.ReadThenFailedStore:
      # Even a refused alias store invalidates authority while leaving every guest byte unchanged.
      assert context.readPointer != nil
      let refused = store(probe.alias, MemoryAddress(65535), AccessWidth(1), RegisterValue(
          probe.replacement))
      assert refused.error == MachineError.Panic
    of LeaseProbe.StoreThenSeal, LeaseProbe.ReadThenUnchangedSeal:
      let published = snapshotMemory(probe.alias)
      assert published.error == MachineError.None
      probe.saved = published.value
    of LeaseProbe.Saturated:
      discard # Saturation is installed before invocation, so no descriptor can be reacquired.
