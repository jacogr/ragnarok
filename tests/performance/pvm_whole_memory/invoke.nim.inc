# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private owned source fragment; the projector removes exactly these three comment lines.

proc invoke*(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile): Invocation =
  ## Ordinary callers have no probe/callback injection surface; all raw lease state is invocation-local.
  invokeInternal(image, writer, registers, nil)

when defined(pvmWholeNativeLeaseControls):
  proc invokeLeaseProbe*(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile,
      mode: LeaseProbe, replacement: uint64): (Invocation, Memory, bool) =
    ## Correctness-only owned alias can seal/COW mid-call; returned values expose no lease or raw pointer.
    let probe = ProbeState(mode: mode, alias: writer, replacement: replacement, fired: false, saved: default(Memory))
    if mode in [LeaseProbe.Saturated, LeaseProbe.ReadThenSaturatingCow]:
      writer.nativeEpoch = high(uint64)-1
      probe.fired = mode == LeaseProbe.Saturated
    let done = invokeInternal(image, writer, registers, cast[pointer](probe))
    assert done.readPointer == nil and done.writePointer == nil and done.epochPointer == nil
    assert done.writer == nil and done.testProbe == nil
    if mode in [LeaseProbe.Saturated, LeaseProbe.ReadThenSaturatingCow]: assert writer.nativeEpoch == high(uint64)
    (done, probe.saved, probe.fired)
