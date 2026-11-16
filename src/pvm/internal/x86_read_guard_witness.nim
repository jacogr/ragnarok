# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included only by the private x86 proof profile. These compiler controls never execute emitted bytes.

## Standalone module discovery has no backend-local types; only private inclusion supplies them.

when declared(X86Block):
  proc witnessX86ReadGuards*() =
    ## Exercise real cold buffers, complete copied read requests and malformed private metadata before publication.
    block missingMappings:
      # A hardware-only operand cannot reinterpret the canonical/unmapped sentinel as a GPR.
      var code = default(X86Block)
      loadX86ResidentRegister(code, default(X86ResidentAccess), 0)
      assert code.error == X86EmissionError.InvalidRegister and takeX86Instructions(code).len == 0
      var checked = default(X86CheckedReadAccess)
      code = default(X86Block)
      writeAccess(code, checked, 0)
      assert code.error == X86EmissionError.InvalidRegister and checked.written == 0
      assert takeX86Instructions(code).len == 0
      code = default(X86Block)
      discard ringHardware(code, default(X86ResidentAccess), 0)
      assert code.error == X86EmissionError.InvalidRegister and takeX86Instructions(code).len == 0

    block incompleteRing:
      # A failed inspection leaves its caller's prior register requirements intact.
      var lanes: X86RingLanes = (used: 7'u32, written: 3'u32)
      assert not tryRingLaneUse(default(NativeRegisterRing), lanes)
      assert lanes == (used: 7'u32, written: 3'u32)

    var body = initNativeReadBody(0, 3, 0, 3, 1)
    for position in 1'u32..2:
      # Both loads are accepted through the ordinary contiguous copied-request API.
      assert addReadBodyOperation(body, position, position,
        NativeOperation(opcode: 130, slots: default(RegisterSlots), immediate: 0))
    assert body.complete and x86CheckedReadInstructions(body).len > 0
    block producerRelocation:
      # Corrupt a real guard relocation after complete request lowering, then recover on the same request.
      let valid = x86CheckedReadInstructions(body)
      assert valid.len > 0
      x86ReadInvalidFixupWitness = true
      let refused = x86CheckedReadInstructions(body)
      x86ReadInvalidFixupWitness = false
      assert refused.len == 0, "resident read published an entry after refusing its body"
      assert x86CheckedReadInstructions(body) == valid
    assert checkedReadStackInstructions(default(NativeReadBody), 0).len == 0
    assert checkedReadResidentInstructions(body, 0).len == 0
    assert checkedReadResidentInstructions(body, 3).len == 0

    block invalidWindow:
      # The displacement precedes this alleged window; refuse before unsigned subtraction or encoding.
      var code = default(X86Block)
      var fixes: seq[X86CycleFixup] = @[]
      var labels = default(array[1+4*int(NativeReadFactLimit), int])
      var next = 1'u8
      emitCheckedReadOperations(code, fixes, labels, body, X86CanonicalAccess(), body.len, 0, next,
        NativeReadWindow(operations: 1, baseLane: 0, first: 1))
      assert code.error == X86EmissionError.InvalidCertificate and takeX86Instructions(code).len == 0

    block invalidLoadEncoding:
      # Invalid private widths never reach range conversion or a default machine load.
      var code = default(X86Block)
      emitCheckedReadValue(code, 0)
      assert code.error == X86EmissionError.UnsupportedOpcode and takeX86Instructions(code).len == 0

    block relocations:
      # A genuine JMP operand gives an independent exact positive displacement before negative cases.
      var labels = default(array[1+4*int(NativeReadFactLimit), int])
      labels[0] = 8
      var code = default(X86Block)
      put(code, [0xe9'u8, 0, 0, 0, 0, 0x90, 0x90, 0x90, 0xc3])
      let fixed = sealCheckedRead(code, @[X86CycleFixup(at: 1, target: 0)], labels)
      assert fixed == @[0xe9'u8, 3, 0, 0, 0, 0x90, 0x90, 0x90, 0xc3]
      for scenario in 0..<6:
        code = default(X86Block)
        put(code, [0xe9'u8, 0, 0, 0, 0, 0x90, 0x90, 0x90, 0xc3])
        labels[0] = 8
        var fix = X86CycleFixup(at: 1, target: 0)
        case scenario
        of 0: fix.at = -1
        of 1: fix.at = high(int)
        of 2: fix.at = 6
        of 3: fix.target = high(uint8)
        of 4: labels[0] = 0
        else: labels[0] = 9
        assert sealCheckedRead(code, @[fix], labels).len == 0
        assert code.error == X86EmissionError.InvalidFixup and takeX86Instructions(code).len == 0

    block regionComposition:
      # Valid source bytes remain usable; invalid rotation/count/extent policy fails before indexing.
      var scalar = default(X86Block)
      emitX86Operation(scalar, 20, default(RegisterSlots), 42)
      emitX86Branch(scalar, 170, default(RegisterSlots), 0, 2, 3)
      var blocks = [X86RegionBlock(header: 0, span: 2, operations: 2,
        yes: 2, no: 3, price: 1, body: move(scalar))]
      assert x86RegionBytes(blocks, false).len > 0
      assert x86RegionBytes(blocks, true).len == 0
      assert x86RegionBytes(blocks, false, byteLimit = 0).len == 0
      assert x86RegionBytes(blocks, false, byteLimit = NativeImageByteLimit+1).len == 0
