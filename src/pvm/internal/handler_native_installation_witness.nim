# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included only by the shared native witness profile; no mutable frame capability is exported.

when declared(FlatFrame):
  func sameInstallation(a, b: FlatNativeInstallation): bool =
    ## Compare every scalar/worker field, including inactive sentinel entries in a failed output.
    if a.key != b.key or a.count != b.count: return false
    for index in 0..<a.patches.len:
      if a.patches[index].offset != b.patches[index].offset or
          a.patches[index].checked != b.patches[index].checked or
          a.patches[index].installed != b.patches[index].installed: return false
    true

  proc witnessFlatNativeInstallation*(source: Program) =
    ## Prove whole-batch planning and restoration, with later-slot damage leaving earlier slots intact.
    ## Synthetic keys exercise private bookkeeping only; the public suite also enters real native images.
    var admitted = prepareFlatPlan(source, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert admitted.error == FlatError.None
    var frame = FlatFrame(plan: takeValue(admitted))
    let original: array[4, FlatHandler] = [flatCharge, flatCharge, flatCharge, flatCharge]
    let installed: array[4, FlatHandler] = [flatNativePure, flatNativeLoop, flatNativePure, flatCharge]
    frame.handlers = @original
    let key = NativeImageKey(slot: 0, generation: 1, ticket: 1, epoch: 1,
      kind: NativeKind.PurePrefix)
    let requests = [FlatNativePatchRequest(offset: 0, handler: flatNativePure),
      FlatNativePatchRequest(offset: 1, handler: flatNativeLoop),
      FlatNativePatchRequest(offset: 2, handler: flatNativePure)]
    var planned = default(FlatNativeInstallation)
    assert planFlatNativePatches(frame, key, requests, planned)
    assert planned.count == 3 and planned.key == key
    for index in 0..<3:
      # Planning neither executes nor modifies the checked table.
      assert frame.handlers[index] == original[index]
      assert planned.patches[index].offset == uint32(index)
      assert planned.patches[index].checked == flatCharge
      assert planned.patches[index].installed == requests[index].handler

    for mutation in 0..5:
      # A failure at the last request must preserve both the caller's sentinel and all predecessors.
      frame.nativeInstallation = default(FlatNativeInstallation)
      frame.handlers = @original
      var altered = requests
      var alteredKey = key
      case mutation
      of 0: altered[2].offset = uint32(frame.handlers.len)
      of 1: altered[2].handler = nil
      of 2: altered[2].offset = altered[0].offset
      of 3: alteredKey.ticket = 0
      of 4:
        # A different owner cannot replace a retained same-slot installation.
        frame.nativeInstallation = planned
        for index in 0..<3:
          let selected = requests[index].handler
          if selected != nil: frame.handlers[index] = selected
        inc alteredKey.ticket
      else:
        # Two existing slots and two new slots exceed the fixed three-slot capacity late in planning.
        frame.nativeInstallation = planned
        frame.nativeInstallation.count = 2
        frame.handlers[0] = flatNativePure
        frame.handlers[1] = flatNativeLoop
        altered = [FlatNativePatchRequest(offset: 1, handler: flatNativeLoop),
          FlatNativePatchRequest(offset: 2, handler: flatNativePure),
          FlatNativePatchRequest(offset: 3, handler: flatNativeLoop)]
      let before = [frame.handlers[0], frame.handlers[1], frame.handlers[2], frame.handlers[3]]
      let installation = frame.nativeInstallation
      var output = FlatNativeInstallation(count: 255)
      output.patches[2].offset = 12345
      let sentinel = output
      assert not planFlatNativePatches(frame, alteredKey, altered, output)
      assert sameInstallation(output, sentinel) and sameInstallation(frame.nativeInstallation, installation)
      for index in 0..<4: assert frame.handlers[index] == before[index]

    for mutation in 0..6:
      # Restoration validates the complete ledger before it changes even its first slot.
      frame.reason = oracle.StepError.None
      frame.nativeInstallation = planned
      frame.handlers = @installed
      case mutation
      of 0: frame.nativeInstallation.count = 4
      of 1: frame.nativeInstallation.patches[2].offset = uint32(frame.handlers.len)
      of 2: frame.nativeInstallation.patches[2].checked = nil
      of 3: frame.nativeInstallation.patches[2].installed = nil
      of 4: frame.handlers[2] = flatCharge
      of 5: frame.nativeInstallation.patches[2].offset = 0
      else: frame.nativeInstallation.key.ticket = 0
      let before = [frame.handlers[0], frame.handlers[1], frame.handlers[2], frame.handlers[3]]
      let installation = frame.nativeInstallation
      assert not flatRestoreNativeInstallation(frame)
      assert frame.reason == oracle.StepError.BackendFailure
      assert sameInstallation(frame.nativeInstallation, installation)
      for index in 0..<4: assert frame.handlers[index] == before[index]

    # A complete valid ledger restores all three predecessors and clears its ownership metadata.
    frame.reason = oracle.StepError.None
    frame.nativeInstallation = planned
    frame.handlers = @installed
    assert flatRestoreNativeInstallation(frame)
    assert frame.nativeInstallation.count == 0 and frame.nativeOriginal == nil
    for index in 0..<4: assert frame.handlers[index] == original[index]
