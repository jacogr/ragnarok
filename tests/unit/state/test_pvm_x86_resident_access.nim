# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private literal scalar/branch residency, canonical bytes and actual six-register SysV controls.
## Full-width relative reads prove both register transactions and late-refusal atomicity.
## Closed loops check mixed resident/spilled lanes, paid-first guards, complete receipts and SysV saves.

import std/[assertions, envvars, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, registers]
import ../../../src/pvm/internal/x86_jit

when not defined(pvmX86ResidentProof):
  assert false, "resident ISA controls require their explicit private define"

const
  Native = defined(linux) and defined(amd64) and not defined(pvmX86JitRefuse)
  Masks = [0'u32, 1, 0x3f, 0x1f80, 0x0aaa, 0x180f]
  Patterns = [0'u8, 17, 128, 255, 0x38, 0xc5]
  Seeds = [0'u64, 31, 64, 0x80000000'u64, 0x8000000000000000'u64, high(uint64)]

when Native and defined(pvmX86Jit):
  import ../../../src/pvm/internal/[native_ir, native_platform, native_read_body, native_fusion]

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Only container framing uses the natural encoder; each original instruction is a literal byte row.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc literalOwner(opcode, pattern: byte): Program =
  ## A marked25-byte instruction plus panic supplies genuine saturated operand coordinates.
  var wire: seq[byte] = @[]
  appendNatural(wire, 0)
  wire.add(0)
  appendNatural(wire, 26)
  wire.add(opcode)
  for index in 0..<24: wire.add(pattern)
  wire.add(0)
  wire.add(1) # Original instruction starts at0.
  wire.add(0)
  wire.add(0)
  wire.add(2) # Panic starts at25; operands remain unmarked.
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(65536), JumpCountLimit(16))
  assert decoded.error == ProgramError.None
  decoded.value

proc initial(seed: uint64): RegisterFile =
  ## Distinct full-width sentinels expose stale resident reads and unwanted writes to all13 lanes.
  result = default(RegisterFile)
  for slot in 0..<13: result[slot] = RegisterValue(seed xor uint64(slot))

proc keepBytes(name: string, bytes: seq[byte]) =
  ## Optional cold byte exports compare the canonical wrapper against the frozen parent emitter.
  let directory = getEnv("RAGNAROK_PVM_RESIDENT_IMAGES")
  if directory.len == 0: return
  var data = newString(bytes.len)
  for index in 0..<bytes.len: data[index] = char(bytes[index])
  try:
    writeFile(directory & "/" & name & ".bin", data)
  except:
    quit 2

proc keepImage(name: string, body: X86Block) =
  ## Builder bytes and actual RX readback have separate artifact names.
  keepBytes(name, x86ResidentImageProof(body))

proc publish(jit: X86Jit, offset: var uint32, body: X86Block): uint32 =
  ## Raw backend controls count one literal operation; no Frame, plan, charge or source authority is invented.
  result = offset
  inc offset
  assert x86Entry(jit, result, 4096) == 0
  when Native:
    assert publishX86Entry(jit, result, result+1, 1, body, shortPrefix = true)

var jit = newX86Jit()
var next = 0'u32
var scalarCases = 0
var branchCases = 0
var loopCases = 0
for numeric in 0..255:
  let opcode = byte(numeric)
  if not supportedX86Opcode(opcode): continue
  for pattern in Patterns:
    let source = literalOwner(opcode, pattern)
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None
    let slots = instructionRegisters(decoded)
    let value = uint64(decoded.value.x)
    var canonical = default(X86Block)
    emitX86Operation(canonical, opcode, slots, value)
    keepImage("scalar-" & $numeric & "-" & $pattern, canonical)
    let plain = publish(jit, next, canonical)
    for mask in Masks:
      # The same opcode switch selects canonical or resident reads/writes, never a second ALU implementation.
      let access = x86ResidentAccess(mask)
      var body = default(X86Block)
      beginX86Resident(body, access)
      emitX86ResidentOperation(body, access, opcode, slots, value)
      endX86Resident(body, access)
      let mapped = publish(jit, next, body)
      when Native:
        for seed in Seeds:
          var expected = initial(seed)
          let evaluated = evaluateRegisters(source, CodeAddress(0), expected)
          assert evaluated.error == RegisterError.None
          expected = evaluated.value
          var baseline = initial(seed)
          assert callX86Entry(jit, plain, baseline) == plain+1
          assert baseline == expected
          var actual = initial(seed)
          let receipt = callX86ResidentAbiProof(jit, mapped, actual)
          assert receipt shr 32 == 1 and actual == expected
          inc scalarCases

for numeric in 81..175:
  let opcode = byte(numeric)
  if opcode notin {81'u8..90, 170..175}: continue
  for pattern in Patterns:
    let source = literalOwner(opcode, pattern)
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None
    let slots = instructionRegisters(decoded)
    let value = uint64(decoded.value.x)
    var canonical = default(X86Block)
    emitX86Branch(canonical, opcode, slots, value, 123, 456)
    keepImage("branch-" & $numeric & "-" & $pattern, canonical)
    let plain = publish(jit, next, canonical)
    for mask in Masks:
      # RAX's selected scalar destination must survive every flush and restored callee-saved register.
      let access = x86ResidentAccess(mask)
      var body = default(X86Block)
      beginX86Resident(body, access)
      emitX86ResidentBranch(body, access, opcode, slots, value, 123, 456)
      endX86Resident(body, access)
      let mapped = publish(jit, next, body)
      when Native:
        for seed in Seeds:
          var baseline = initial(seed)
          let before = baseline
          let expected = callX86ResidentAbiProof(jit, plain, baseline)
          assert expected shr 32 == 1 and baseline == before
          var actual = before
          let receipt = callX86ResidentAbiProof(jit, mapped, actual)
          assert receipt == expected and actual == before
          inc branchCases

block everyHardwareDestination:
  # Fully aliased ADDs individually read/write RBX,RBP,R12,R13,R14,R15, not only their save slots.
  let access = x86ResidentAccess(0x3f)
  for lane in 0..<6:
    let source = literalOwner(149, byte(lane*17))
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None
    var body = default(X86Block)
    beginX86Resident(body, access)
    emitX86ResidentOperation(body, access, 149, instructionRegisters(decoded), 7)
    endX86Resident(body, access)
    let mapped = publish(jit, next, body)
    when Native:
      var actual = initial(0x8000000000000000'u64)
      var expected = actual
      expected[lane] = RegisterValue(uint64(expected[lane])+7)
      assert callX86ResidentAbiProof(jit, mapped, actual) shr 32 == 1
      assert actual == expected

block contextAndCurrentOperands:
  # Sequential mapped/unmapped writes then a mapped comparison expose current values, not entry snapshots.
  let access = x86ResidentAccess(0x1f80)
  let source = literalOwner(149, 0x88) # ADD64 R8,R8,+immediate.
  let decoded = instruction(source, CodeAddress(0))
  assert decoded.error == ProgramError.None
  let slots = instructionRegisters(decoded)
  var body = default(X86Block)
  beginX86Resident(body, access)
  emitX86ResidentContextProof(body)
  emitX86ResidentOperation(body, access, 149, slots, 1)
  emitX86ResidentOperation(body, access, 149, slots, 2)
  emitX86ResidentBranch(body, access, 81, slots, 103, 123, 456)
  endX86Resident(body, access)
  if getEnv("RAGNAROK_PVM_RESIDENT_BAD_ABI") == "1": clobberX86ResidentAbiProof(body)
  keepImage("resident-context", body)
  let mapped = publish(jit, next, body)
  when Native:
    var publishedBytes: seq[byte] = @[]
    var expectedBytes = x86ResidentImageProof(body)
    expectedBytes.add(0xc3) # Actual publisher appends the same final RET.
    assert copyX86ResidentImageProof(jit, mapped, uint32(expectedBytes.len), publishedBytes)
    assert publishedBytes == expectedBytes
    keepBytes("resident-context-rx", publishedBytes)
    var actual = initial(0)
    actual[8] = RegisterValue(100)
    var expected = actual
    expected[8] = RegisterValue(103)
    let receipt = callX86ResidentAbiProof(jit, mapped, actual, true)
    assert receipt == ((1'u64 shl 32) or 123'u64) and actual == expected
    assert getEnv("RAGNAROK_PVM_RESIDENT_BAD_ABI") != "1", "callee-clobber probe missed"

when Native and defined(pvmX86Jit):
  type ReadWidthCase = object
    ## Literal bytes and full-width oracles distinguish the four newly admitted load forms.
    opcode: byte
    width: range[1..8]
    data, changed: array[8, byte]
    value, changedValue: uint64
    chainOffset: uint32

  const
    ReadWidths = [
      ReadWidthCase(opcode: 125, width: 1, data: [0x80'u8, 0, 0, 0, 0, 0, 0, 0],
        changed: [0x7f'u8, 0, 0, 0, 0, 0, 0, 0], value: 0xffffffffffffff80'u64,
        changedValue: 0x7f, chainOffset: 0x20081),
      ReadWidthCase(opcode: 126, width: 2, data: [1'u8, 0x80, 0, 0, 0, 0, 0, 0],
        changed: [0xff'u8, 0xff, 0, 0, 0, 0, 0, 0], value: 0x8001,
        changedValue: 0xffff, chainOffset: 0x18000),
      ReadWidthCase(opcode: 127, width: 2, data: [1'u8, 0x80, 0, 0, 0, 0, 0, 0],
        changed: [0xff'u8, 0x7f, 0, 0, 0, 0, 0, 0], value: 0xffffffffffff8001'u64,
        changedValue: 0x7fff, chainOffset: 0x28000),
      ReadWidthCase(opcode: 128, width: 4, data: [1'u8, 0, 0, 0x80, 0, 0, 0, 0],
        changed: [0xff'u8, 0xff, 0xff, 0xff, 0, 0, 0, 0], value: 0x80000001'u64,
        changedValue: 0xffffffff'u64, chainOffset: 0x80020000'u32)]
    ReadWideBytes = [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]
    ReadWideValue = 0xfedcba9876543210'u64

  proc widthOperation(opcode: byte, destination, base: range[0..12],
      offset: uint32): NativeOperation =
    ## Decode one marked literal six-byte instruction; no private register-slot constructor is used.
    let packed = byte(int(destination) or (int(base) shl 4))
    let wire = @[0'u8, 0, 7, opcode, packed, byte(offset and 255),
      byte((offset shr 8) and 255), byte((offset shr 16) and 255),
      byte((offset shr 24) and 255), 0, 0x41]
    let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(16), JumpCountLimit(0))
    assert decoded.error == ProgramError.None
    let inst = instruction(decoded.value, CodeAddress(0))
    assert inst.error == ProgramError.None
    let slots = instructionRegisters(inst)
    assert slots.aIndex == destination
    if opcode == 51:
      # The scalar load contributes one distinct dirty lane without another memory access.
      assert slots.destinationIndex == destination
    else:
      # Genuine relative read operands keep both alias coordinates and the original clipped offset.
      assert nativeReadOpcode(opcode) and slots.bIndex == base
    assert uint32(uint64(inst.value.x) and 0xffffffff'u64) == offset
    NativeOperation(opcode: opcode, slots: slots, immediate: uint64(inst.value.x))

  proc widthBody(row: ReadWidthCase, dirty: range[6..7], variant: range[0..2]): NativeReadBody =
    ## Six dirty lanes select resident registers; seven force a stack transaction of the same reads.
    let firstOpcode = if variant == 1: 130'u8 else: row.opcode
    let lastOpcode = if variant == 1: row.opcode else: 130'u8
    let lastBase: range[0..12] = if variant == 2: 1 else: 8
    let lastOffset = if variant == 2: row.chainOffset else: 0'u32
    var operations = @[widthOperation(firstOpcode, 1, 1, 0x10002)]
    for slot in 2..<dirty:
      # These distinct scalar destinations expose late publication in every saved hardware lane.
      operations.add(widthOperation(51, range[0..12](slot), 0, uint32(32+slot)))
    operations.add(widthOperation(lastOpcode, 0, range[0..12](lastBase), lastOffset))
    assert operations.len == dirty
    result = initNativeReadBody(40, uint32(41+dirty), 10, uint32(11+dirty), 1)
    for index, operation in operations:
      # Copied geometry is complete and consecutive; the old leading noop/terminal remain accounted.
      assert addReadBodyOperation(result, uint32(41+index), uint32(11+index), operation)
    assert result.complete

  block checkedReadAbiAndRefusal:
    # The six dirty lanes exercise every SysV save while the late U64 can still refuse.
    let wire = [0'u8, 0, 27, 2, 124, 0x11, 2, 0, 1, 149, 0x11, 0, 0, 1,
      129, 0x12, 0xff, 149, 0x33, 1, 51, 6, 0x26, 51, 7, 0x37, 130, 0x54, 1, 0,
      0x43, 0x48, 0x92, 0x06]
    let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
    assert decoded.error == ProgramError.None
    let owner = decoded.value
    let terminal = instruction(owner, CodeAddress(25))
    assert terminal.error == ProgramError.None and terminal.value.opcode == 1
    assert instructionTargetStartsBlock(terminal)
    var body = initNativeReadBody(40, 48, 10, 18, 1)
    for index, pc in [1'u32, 6, 11, 14, 17, 20, 23]:
      let inst = instruction(owner, CodeAddress(pc))
      assert inst.error == ProgramError.None
      let operation = NativeOperation(opcode: inst.value.opcode, slots: instructionRegisters(inst),
        immediate: uint64(inst.value.x))
      assert addReadBodyOperation(body, uint32(41+index), uint32(11+index), operation)
    assert body.complete
    let image = lowerNativeReadBody(body)
    assert isReadBody(image)

    var original = initial(0x1234567800000000'u64)
    original[1] = RegisterValue(0x00000001fffffffe'u64)
    original[5] = RegisterValue(0x20000)
    var expected = original
    expected[1] = RegisterValue(0x10080) # The aliased U8 consumes old r1 before writing it.
    expected[2] = RegisterValue(0xffffffff80000001'u64)
    expected[3] = RegisterValue(0x1234567800000004'u64) # Mapped scalar read before its first write.
    expected[4] = RegisterValue(0xfedcba9876543210'u64)
    expected[6] = RegisterValue(0x26)
    expected[7] = RegisterValue(0x37)
    var byteRegion = [0xa5'u8, 0x80]
    var signedRegion = [1'u8, 0, 0, 0x80]
    var wideRegion = [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]
    var context = [initNativeReadRegion(0xffff'u64, byteRegion),
      initNativeReadRegion(0x1007f'u64, signedRegion),
      initNativeReadRegion(0x20000'u64, wideRegion)]
    var actual = original
    assert enterNativeReadBodyAbiProof(image, actual, context) and actual == expected
    context[2] = initNativeReadRegion(0x20000'u64, wideRegion.toOpenArray(0, 6))
    actual = original
    assert not enterNativeReadBodyAbiProof(image, actual, context) and actual == original
    context[2] = initNativeReadRegion(0x20000'u64, wideRegion)
    assert enterNativeReadBodyAbiProof(image, actual, context) and actual == expected
    assert byteRegion == [0xa5'u8, 0x80] and signedRegion == [1'u8, 0, 0, 0x80]
    assert wideRegion == [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]

  block newReadWidthsBothTransactions:
    # Every new form uses the actual published two-borrow leaf and existing six-GPR ABI sentinel.
    for row in ReadWidths:
      for dirty in 6..7:
        for variant in 0..2:
          # New→U64, U64→new and new→dependent-U64 expose both late widths and current aliases.
          let body = widthBody(row, dirty, variant)
          keepBytes("read-width-" & $row.opcode & "-dirty-" & $dirty & "-variant-" & $variant,
            x86CheckedReadInstructions(body))
          let image = lowerNativeReadBody(body)
          assert isReadBody(image)
          let firstWidth = if variant == 1: 8 else: row.width
          let lastWidth = if variant == 1: row.width else: 8
          assert firstWidth in 1..8 and lastWidth in 1..8
          var firstData = default(array[9, byte])
          firstData[0] = 0xa5
          var lastData = default(array[8, byte])
          for index in 0..<firstWidth:
            # The clipped lower extent drops a canary and presents an exact-fit, potentially unaligned load.
            firstData[index+1] = if variant == 1: ReadWideBytes[index] else: row.data[index]
          for index in 0..<8:
            # The later extent starts at an unaligned guest address; trailing backing bytes remain canaries.
            lastData[index] = if variant == 1: row.data[index] else: ReadWideBytes[index]
          let originalFirst = firstData
          let originalLast = lastData
          var original = initial(0x1234567800000000'u64)
          original[1] = RegisterValue(0x00000001fffffffe'u64)
          original[8] = RegisterValue(0x1234567800020001'u64)
          var expected = original
          expected[1] = RegisterValue(if variant == 1: ReadWideValue else: row.value)
          expected[0] = RegisterValue(if variant == 1: row.value else: ReadWideValue)
          for slot in 2..<dirty:
            # Literal scalar values distinguish every dirty destination from its original sentinel.
            expected[slot] = RegisterValue(uint64(32+slot))
          var context = default(NativeReadContext)
          context[0] = initNativeReadRegion(0xffff, firstData.toOpenArray(0, firstWidth))
          for truncated in [false, true, false]:
            # A late failed guard must discard earlier reads and scalar writes before a recovered call.
            if truncated and lastWidth == 1:
              # A width-one short extent is empty and has no usable pointer.
              context[1] = default(NativeReadRegion)
            else:
              # Exact fit succeeds; a width-minus-one extent refuses before touching its host pointer.
              let length = lastWidth-(if truncated: 1 else: 0)
              assert length in 1..8
              context[1] = initNativeReadRegion(0x20001, lastData.toOpenArray(0, length-1))
            var actual = original
            assert enterNativeReadBodyAbiProof(image, actual, context) == (not truncated)
            assert actual == (if truncated: original else: expected)
            assert firstData == originalFirst and lastData == originalLast
          if variant != 2:
            # The same image must consume changed bytes; a fixed dependent address is tested above instead.
            if variant == 0:
              # Signed positive and unsigned high-bit alternatives replace the earlier aliased read result.
              for index in 0..<row.width: firstData[index+1] = row.changed[index]
              expected[1] = RegisterValue(row.changedValue)
            else:
              # A changed final value must also clear/sign-extend all upper destination bits.
              for index in 0..<row.width: lastData[index] = row.changed[index]
              expected[0] = RegisterValue(row.changedValue)
            let changedFirst = firstData
            let changedLast = lastData
            var actual = original
            assert enterNativeReadBodyAbiProof(image, actual, context) and actual == expected
            assert firstData == changedFirst and lastData == changedLast

when Native and defined(pvmX86Jit):
  proc loopIncrement(slot: range[0..12]): RegisterSlots =
    ## Literal ADD64 rN,rN,1 yields genuine decoded aliased source/destination coordinates.
    let wire = [0'u8, 0, 5, 149, byte(int(slot) or (int(slot) shl 4)), 1, 50, 0, 9]
    let owner = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
    assert owner.error == ProgramError.None
    let decoded = instruction(owner.value, CodeAddress(0))
    assert decoded.error == ProgramError.None and decoded.value.opcode == 149
    instructionRegisters(decoded)

  block closedLoopResidency:
    # A thirteen-lane body must spill while its selected bank still saves all six SysV GPRs.
    for width in [2, 6, 7, 12, 13]:
      for immediate in [false, true]:
        # A separate register bound stays read-only; the thirteen-writer case uses an immediate.
        if width == 13 and not immediate: continue
        let counter = width-1
        let branchOwner = literalOwner((if immediate: 82'u8 else: 172'u8),
          byte(counter or (if immediate: 0 else: 12 shl 4)))
        let branch = instruction(branchOwner, CodeAddress(0))
        assert branch.error == ProgramError.None
        for price in [3'u64, 0x100000001'u64]:
          # Both compact and full-width context debits share one resident publication epilogue.
          var span = initNativeSpan(41, 0, 1)
          for slot in 0..12:
            # The fixed guest-file extent proves the decoded lane before selecting the body width.
            if slot >= width: break
            assert span.add(149, loopIncrement(slot), 1, uint32(slot), uint32(42+slot))
          let sourceSpan = uint32(width+1)
          span.promote(NativeLoopInfo(header: 40, exitHeader: 80, sourceSpan: sourceSpan,
            price: price, slots: instructionRegisters(branch),
            rightKind: (if immediate: NativeLoopRightKind.Immediate else: NativeLoopRightKind.Register),
            rightImmediate: 8))
          let image = lowerNative(span)
          assert image.ready and image.kind == NativeKind.ClosedRegisterLoop
          for seed in [0'u64, high(uint64)-3]:
            for gas in [0'u64, price-1, price, price*16]:
              for remaining in [0'u64, uint64(sourceSpan)-1, uint64(sourceSpan), uint64(
                  sourceSpan)*16]:
                # A plain scalar oracle applies the paid body before either next-visit guard.
                var expected = initial(seed)
                expected[counter] = RegisterValue(0)
                if not immediate: expected[12] = RegisterValue(8)
                var actual = expected
                var ledger = NativeLoopContext(gas: gas, remaining: remaining, visits: 0)
                var context = ledger
                var next = 40'u32
                while true:
                  # Every admitted scalar writes exactly once, including canonical spilled lanes.
                  for slot in 0..<width:
                    expected[slot] = RegisterValue(uint64(expected[slot])+1)
                  inc ledger.visits
                  if uint64(expected[counter]) >= 8:
                    next = 80
                    break
                  if ledger.gas < price or ledger.remaining < uint64(sourceSpan): break
                  ledger.gas -= price
                  ledger.remaining -= uint64(sourceSpan)
                assert enterNativeLoop(image, actual, context) == next
                assert actual == expected
                assert context.gas == ledger.gas and context.remaining == ledger.remaining and
                  context.visits == ledger.visits
                inc loopCases

when Native and defined(pvmX86Jit):
  proc fusionPressure(excluded: uint32, header: uint32): NativeFusionBlock =
    ## Six unrelated lanes dominate allocation while all13 benign self-moves link to a checked exit.
    ## Tested operands therefore exercise the SIMD bank; no scalar implementation is duplicated.
    result = NativeFusionBlock(header: header, first: header, price: 5,
      targets: [1000'u32+header, NativeEntryFailure], branch: NativeOperation(opcode: 40))
    var hot = 0
    var count = 0
    for slot in 0..12:
      let pressure = (excluded and (1'u32 shl slot)) == 0 and hot < 6
      if pressure: inc hot
      let copies = if pressure: 3 else: 1
      let owner = literalOwner(100, byte(slot*17))
      let decoded = instruction(owner, CodeAddress(0))
      assert decoded.error == ProgramError.None
      for repetition in 0..<copies:
        result.operations[count] = NativeOperation(opcode: 100, slots: instructionRegisters(decoded))
        inc count
    assert hot == 6 and count == 25
    result.terminal = header+uint32(count)+1
    result.span = uint32(count)+1

  block fusionSimdOperands:
    # Exercise scalar aliases and every predicate with full-width SIMD inputs through real linked
    # images. The original GP register evaluator/canonical predicate supplies the independent oracle.
    const fusionPatterns = [0'u8, 17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204,
      128, 255, 0x38, 0xc5]
    var cases = 0
    for numeric in 0..255:
      let opcode = byte(numeric)
      let scalar = supportedX86Opcode(opcode)
      let predicate = opcode in {81'u8..90, 170..175}
      if not scalar and not predicate: continue
      for pattern in fusionPatterns:
        let owner = literalOwner(opcode, pattern)
        let decoded = instruction(owner, CodeAddress(0))
        assert decoded.error == ProgramError.None
        let slots = instructionRegisters(decoded)
        let value = uint64(decoded.value.x)
        let excluded = (1'u32 shl int(slots.aIndex)) or (1'u32 shl int(slots.bIndex)) or
          (1'u32 shl int(slots.destinationIndex))
        var first = NativeFusionBlock(header: 10, first: 10, terminal: (
            if scalar: 12'u32 else: 11'u32),
          span: (if scalar: 2'u32 else: 1'u32), price: 3, targets: [100'u32, NativeEntryFailure],
          branch: NativeOperation(opcode: 40))
        var plain = 0'u32
        if scalar:
          first.operations[0] = NativeOperation(opcode: opcode, slots: slots, immediate: value)
        else:
          first.targets[1] = 200
          first.branch = NativeOperation(opcode: opcode, slots: slots, immediate: value)
          var body = default(X86Block)
          emitX86Branch(body, opcode, slots, value, 200, 100)
          plain = publish(jit, next, body)
        var blocks = @[first, fusionPressure(excluded, 100)]
        if predicate: blocks.add(fusionPressure(excluded, 200))
        let image = lowerNativeFusion(blocks)
        assert image.ready and nativeFusionEntry(image, 0) and nativeFusionEntry(image, 1)
        for seed in Seeds:
          for refusal in 0..4:
            # Both reservation guards are exercised before any block and after the tested operation.
            let gas = if refusal == 1: 2'u64 elif refusal == 3: 7'u64 else: high(uint64)
            let quota = if refusal == 2: 0'u64 elif refusal == 4: uint64(first.span) else: 1000'u64
            var actual = initial(seed)
            var expected = actual
            var target = 100'u32
            if scalar:
              let evaluated = evaluateRegisters(owner, CodeAddress(0), expected)
              assert evaluated.error == RegisterError.None
              expected = evaluated.value
            else:
              # The frozen canonical predicate runs independently of the new operand policy.
              target = uint32(callX86ResidentAbiProof(jit, plain, expected) and 0xffffffff'u64)
              assert target in [100'u32, 200] and expected == actual
            let idle = refusal in [1, 2]
            if idle: expected = actual
            var context = NativeFusionContext(gas: gas, remaining: quota)
            let observed = enterNativeFusion(image, 0, actual, context)
            let visits = if idle: 0'u64 elif refusal in [3, 4]: 1'u64 else: 2'u64
            let expectedNext = if idle: 10'u32 elif visits == 1: target else: target+1000
            assert observed == expectedNext and actual == expected
            assert context.visits == visits and context.paid == 0
            assert context.gas == gas-(if visits == 0: 0'u64 elif visits == 1: 3'u64 else: 8'u64)
            assert context.remaining == quota-(if visits == 0: 0'u64 elif visits == 1:
              uint64(first.span) else: uint64(first.span)+26)
            if visits > 0: assert (context.path[0] and 255) == 1
            if visits == 2: assert ((context.path[0] shr 8) and 255) == (if target ==
                100: 2'u64 else: 3'u64)
            inc cases
    assert cases == (59+16)*fusionPatterns.len*Seeds.len*5

when Native:
  # Fifty-nine scalar opcodes cover every pattern, resident mask and initial seed.
  assert scalarCases == 12744, "resident scalar coverage: " & $scalarCases
  assert branchCases == 3456, "resident branch coverage: " & $branchCases
  when defined(pvmX86Jit):
    assert loopCases == 576, "resident closed-loop coverage: " & $loopCases
assert next < 4096
stdout.writeLine("X86_RESIDENT_ACCESS_OK")
