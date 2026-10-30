# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Checked-loop execution: literal byte effects and independent single-step CPU/accounting/fault outcomes.
import std/[assertions, syncio]
import ../../../src/pvm/internal/handler_stream
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas
proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Test framing uses the independent natural codec without borrowing program storage.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len:
    # Only the explicitly encoded prefix belongs to the output.
    bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Explicit instruction boundaries support long blocks and saturated operands without a production assembler.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Caller-provided operand bytes never become instruction boundaries.
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes: seq[byte] = @[]
  appendNatural(bytes, uint64(jumps.len))
  bytes.add(if jumps.len == 0: 0'u8 else: 4'u8)
  appendNatural(bytes, uint64(code.len))
  for target in jumps:
    # Fixed four-byte table entries are independent of operand decoding and may deliberately name invalid code targets.
    for shift in 0..<4: bytes.add(byte((uint64(target) shr (shift*8)) and 255))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts:
    # Mark the original opcode positions only.
    mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(1024))
  assert decoded.error == ProgramError.None, "invalid independent bytecode fixture"
  decoded.value

proc verifyControl(frame: var FlatFrame, program: Program, info: MachineInfo, budget: uint64,
    images: openArray[PageImage] = []) =
  ## Bounded single-step execution independently checks charged prefixes, target PCs and terminal normalization.
  let memory = captureMemory(images, PageLimit(uint32(max(2, images.len)))).value
  var expected = captureMachine(program, memory, info).value
  var exit = StepExit.Continued
  var reason = StepError.StepLimitExceeded
  var consumed = 0'u64
  var wantedHost = HostCallId(0)
  var wantedFault = PageAddress(0)
  var wantedHostPc = CodeAddress(0)
  for attempted in 0'u64..<budget:
    # One-instruction plans cannot take the complete-block fusion under test.
    let attemptedPc = machineInfo(expected).value.pc
    let next = stepOnce(expected, GasCycleLimit(100000))
    assert next.error == StepError.None, "single-step oracle refused a valid fixture"
    expected = next.value.machine
    exit = next.value.exit
    if exit != StepExit.OutOfGas:
      # Gas refusal is the only stopped instruction that does not consume its source attempt.
      inc consumed
    if exit == StepExit.Host:
      # Psi_1 advances the published host PC; recursive suspension retains the attempted instruction.
      wantedHost = next.value.hostCall
      wantedHostPc = attemptedPc
    if exit == StepExit.Fault:
      # Preserve the independently reported page rather than deriving it from the final address register.
      wantedFault = next.value.faultPage
    if exit != StepExit.Continued:
      # Terminal outcomes end the bounded oracle before another source attempt.
      reason = StepError.None
      break
  resetFlatFrame(frame, info)
  runFlat(frame, budget)
  let wanted = machineInfo(expected).value
  if frame.reason != reason or frame.exit != exit:
    # Emit the failing budget and both outcomes before the assertion.
    echo "CONTROL_EXIT,", budget, ",", reason, ",", exit, ",", frame.reason, ",", frame.exit
  assert frame.reason == reason and frame.exit == exit, "checked-loop exit disagrees with single stepping"
  if frame.remaining != budget-consumed:
    # A paid prefix or gas refusal must not hide an extra or missing attempt.
    echo "REMAINING,", budget, ",", consumed, ",", frame.remaining, ",", exit
  assert frame.remaining == budget-consumed, "checked-loop source-attempt count mismatch"
  if exit == StepExit.Host:
    # The recursive boundary exposes the actual suspended host call.
    assert frame.hostCall == wantedHost, "checked-loop suspended host call mismatch"
  if exit == StepExit.Fault:
    # The checked worker must report the same refused page as the source instruction.
    assert frame.faultPage == wantedFault
  let pc = if exit in [StepExit.Halt, StepExit.Panic]: 0'u64
    elif exit == StepExit.Host: uint64(wantedHostPc)
    else: uint64(wanted.pc)
  if uint64(frame.info.pc) != pc:
    # Include both coordinates when partial or recursive normalization differs.
    echo "CONTROL_PC,", uint64(frame.info.pc), ",", pc
  assert uint64(frame.info.pc) == pc, "checked-loop exit PC mismatch"
  assert frame.info.gas == wanted.gas and frame.info.gasDeficit == wanted.gasDeficit, "checked-loop gas mismatch"
  assert frame.info.blockCharged == wanted.blockCharged, "checked-loop paid state mismatch"
  for slot in 0..<13:
    # All source-visible register mutations survive faults, limits and aliased destinations exactly.
    assert frame.info.registers[slot] == wanted.registers[slot]
  checkFlatSource(frame, images)
  if images.len != 0:
    # The independent single-step machine owns expected store effects; every original input snapshot stays immutable.
    let published = flatMemorySnapshot(frame)
    let expectedMemory = memoryOf(expected)
    assert expectedMemory.error == MachineError.None, "single-step oracle lost its memory owner"
    for image in images:
      let actual = pageImage(published, image.index)
      let wantedPage = pageImage(expectedMemory.value, image.index)
      let original = pageImage(memory, image.index)
      assert actual.error == MachineError.None and wantedPage.error == MachineError.None, "checked-loop expected page is missing"
      assert original.error == MachineError.None, "original source page is missing"
      assert actual.value.access == wantedPage.value.access and actual.value.bytes ==
          wantedPage.value.bytes, "checked-loop page permission or bytes mismatch"
      assert original.value.access == image.access and original.value.bytes == image.bytes, "original source snapshot changed"

proc checkedPlan(program: Program): FlatPlan =
  ## Explicit interpretation exercises the checked fusion even in native-enabled compilation profiles.
  var prepared = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(),
      allowNative = false)
  assert prepared.error == FlatError.None, "checked-loop plan admission failed"
  takeValue(prepared)

let loopProgram = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0],
  @[149'u8, 0x00, 1], @[149'u8, 0x11, 1],
  @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
let plan = checkedPlan(loopProgram)
let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
info.registers[0] = RegisterValue(65536)
info.registers[1] = RegisterValue(0x1234)
info.registers[2] = RegisterValue(0xa5)
info.registers[3] = RegisterValue(65552)
var frame = newFlatFrame(plan, [page], info)
for warm in 0..<6:
  # Multiple complete calls prove the cold arm resolution and later resident loop both execute.
  verifyControl(frame, loopProgram, info, 100, [page])
let first = flatMemorySnapshot(frame)
let bytes = pageImage(first, PageIndex(16)).value.bytes
assert bytes[0] == 0x34 and bytes[1] == 0x35 and bytes[15] == 0x43, "literal rising store bytes mismatch"
assert frame.info.registers[0] == RegisterValue(65552), "literal final address mismatch"
assert frame.info.registers[1] == RegisterValue(0x1244), "literal final source value mismatch"

var count = 0
for layout in 0..<5:
  # Independent byte/permission/empty/protected/high-page maps cover success and precise memory failure.
  var pages: seq[PageImage] = @[]
  var seed = info
  if layout != 2 and layout != 3:
    # Other cases deliberately supply no writable mapping at the effective address.
    var current = page
    if layout == 1:
      # A present read-only page must refuse the store after its prefix has executed.
      current.access = PageAccess.ReadOnly
    if layout == 4:
      # The final valid byte of the address space must remain writable without wraparound.
      current.index = PageIndex(1048575)
      seed.registers[0] = RegisterValue(0xfffffff0'u64)
      seed.registers[3] = RegisterValue(0x100000000'u64)
    pages.add(current)
  if layout == 3:
    # The protected range follows its GP panic ordering, separately from an unmapped-page fault.
    seed.registers[0] = RegisterValue(65535)
    seed.registers[3] = RegisterValue(65551)
  assert replaceFlatMemoryChecked(frame, pages, seed) == FlatError.None, "checked-loop layout replacement failed"
  for paid in [false, true]:
    # Paid reentry skips only its first block charge, even when available gas is zero.
    for gas in [0'u64, 1, 4, 5, 100, 1000, high(uint64)]:
      # These values bracket complete block charges and retain saturated arithmetic coverage.
      for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 79, 80, 81, 100, high(uint64)]:
        # Check early partials, the last backedge/terminal boundary and unbounded remaining attempts.
        var input = seed
        input.gas = MachineGas(gas)
        input.blockCharged = paid
        verifyControl(frame, loopProgram, input, budget, pages)
        inc count
# Every source boundary across all sixteen iterations is independently checked in both paid states.
assert replaceFlatMemoryChecked(frame, [page], info) == FlatError.None, "checked-loop writable layout restore failed"
for paid in [false, true]:
  # Sweep every interior coordinate with both newly charged and prepaid entry.
  for budget in 0'u64..83'u64:
    # The independent oracle stops at this exact original source-instruction boundary.
    var input = info
    input.blockCharged = paid
    verifyControl(frame, loopProgram, input, budget, [page])
    inc count

for destination in [0, 1, 2, 3, 4]:
  # The checked path may legally alias prefix output with address, data, shift, limit or other registers.
  let prefix = if destination == 0: @[198'u8, 0x40, 0] else: @[198'u8, 0x41, byte(destination)]
  let alias = owner([prefix, @[120'u8, 0x02, 0], @[149'u8, 0x00, 1], @[149'u8, 0x11, 1],
    @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
  var actual = newFlatFrame(checkedPlan(alias), [page], info)
  for warm in 0..<6:
    # Exercise both first resolution and the subsequently cached complete-loop worker.
    verifyControl(actual, alias, info, 100, [page])
  for paid in [false, true]:
    # Aliased operands must preserve the same prefix and store order at partial boundaries.
    for budget in 0'u64..12'u64:
      # Two iterations include the branch handoff and the next reservation after an aliasing mutation.
      var input = info
      input.blockCharged = paid
      verifyControl(actual, alias, input, budget, [page])
      inc count
  if destination == 0:
    # A nonidentity address-prefix fault still publishes that prefix before the refused store.
    var input = info
    input.registers[0] = RegisterValue(262144)
    input.registers[4] = RegisterValue(1)
    verifyControl(actual, alias, input, 100, [page])
    assert actual.exit == StepExit.Fault and actual.info.registers[0] == RegisterValue(131072), "address prefix did not survive its store fault"
    assert uint64(actual.info.pc) == 3, "fault did not stop at the original store PC"
    inc count
    # Repair at the faulting store retries the paid suffix without reexecuting its address prefix.
    let failed = actual.info
    let repaired = PageImage(index: PageIndex(32), access: PageAccess.ReadWrite)
    assert replaceFlatMemoryChecked(actual, [page, repaired], failed) == FlatError.None
    verifyControl(actual, alias, failed, 1, [page, repaired])
    assert pageImage(flatMemorySnapshot(actual), PageIndex(32)).value.bytes[0] == 0xa5
    assert actual.info.gas == failed.gas and actual.info.blockCharged
    assert uint64(actual.info.pc) == 6
    verifyControl(actual, alias, failed, 100, [page, repaired])
    inc count

var nextPage = page
nextPage.index = PageIndex(17)
var crossing = info
crossing.registers[0] = RegisterValue(69626)
crossing.registers[3] = RegisterValue(69642)
assert replaceFlatMemoryChecked(frame, [page, nextPage], crossing) == FlatError.None, "crossing layout replacement failed"
verifyControl(frame, loopProgram, crossing, 100, [page, nextPage])
let left = pageImage(flatMemorySnapshot(frame), PageIndex(16)).value.bytes
let right = pageImage(flatMemorySnapshot(frame), PageIndex(17)).value.bytes
assert left[4090] == 0x34 and left[4095] == 0x39 and right[0] == 0x3a and right[9] == 0x43, "crossing literal store bytes mismatch"
assert pageImage(first, PageIndex(16)).value.bytes[0] == 0x34, "retained pre-reset snapshot changed"

# Moving the resolved stream to a fresh invocation must not retain the old frame's physical-memory coordinates.
var active = takeFlatStream(frame)
var freshInfo = info
freshInfo.registers[1] = RegisterValue(0x1254)
var fresh = newFlatFrame(plan, [page], freshInfo)
restoreFlatStream(fresh, active)
verifyControl(fresh, loopProgram, freshInfo, 100, [page])
assert pageImage(flatMemorySnapshot(fresh), PageIndex(16)).value.bytes[0] == 0x54
assert pageImage(flatMemorySnapshot(fresh), PageIndex(16)).value.bytes[15] == 0x63
assert pageImage(first, PageIndex(16)).value.bytes[0] == 0x34

# A genuine accepted host epoch preserves old observations and reuses the same charged-loop cache.
let hosted = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0], @[149'u8, 0x00, 1],
  @[149'u8, 0x11, 1], @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[10'u8, 7],
  @[40'u8, 0xec, 0xff, 0xff, 0xff]])
var hostFrame = newFlatFrame(checkedPlan(hosted), [page], info)
verifyControl(hostFrame, hosted, info, 100, [page])
assert hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Host, "initial checked-loop host exit mismatch"
let observed = observeFlatHostMemory(hostFrame)
assert pageImage(observed, PageIndex(16)).value.bytes[0] == 0x34, "initial host observation bytes mismatch"
let posterior = writeBytes(observed, MemoryAddress(65536), [0xee'u8], MemoryByteLimit(1)).value
let posteriorImages = memoryImages(posterior).value
var resumed = hostFrame.info.registers
resumed[0] = RegisterValue(65536)
resumed[1] = RegisterValue(0x1284)
assert resumeFlatHostMemory(hostFrame, posterior, MachineGas(100000), resumed) == StepError.None, "valid host posterior refused"
let resumedInfo = hostFrame.info
verifyControl(hostFrame, hosted, resumedInfo, 100, posteriorImages)
if hostFrame.reason != StepError.None or hostFrame.exit != StepExit.Host:
  # Include the actual resumed exit and key registers if the host epoch did not complete.
  echo "HOST_REENTRY,", hostFrame.reason, ",", hostFrame.exit, ",", uint64(hostFrame.info.pc), ",",
      uint64(hostFrame.info.registers[0]), ",", uint64(hostFrame.info.registers[1])
assert hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Host, "checked-loop host reentry exit mismatch"
let after = flatMemorySnapshot(hostFrame)
assert pageImage(after, PageIndex(16)).value.bytes[0] == 0x84, "host epoch did not publish the new first store"
assert pageImage(after, PageIndex(16)).value.bytes[15] == 0x93, "host epoch did not publish the new last store"
assert pageImage(observed, PageIndex(16)).value.bytes[0] == 0x34, "old host observation changed"
assert pageImage(posterior, PageIndex(16)).value.bytes[0] == 0xee, "accepted host posterior changed"
checkFlatSource(hostFrame, posteriorImages)
echo "CHECKED_STORE_LOOP_CASES,", count

block:
  # Keep the original scalar-loop corpus above; this second dataflow can additionally project four stores into one word.
  let wordProgram = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0], @[149'u8, 0x00, 1],
    @[149'u8, 0x44, 8], @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
  let wordPlan = checkedPlan(wordProgram)
  var wordInfo = info
  wordInfo.registers[1] = RegisterValue(0x12345678)
  var words = newFlatFrame(wordPlan, [page], wordInfo)
  for warm in 0..<6:
    # First-use branch resolution and later complete word batches must have identical source-visible effects.
    verifyControl(words, wordProgram, wordInfo, 100, [page])
  let originalWords = flatMemorySnapshot(words)
  let literal = pageImage(originalWords, PageIndex(16)).value.bytes
  assert literal[0] == 0x78 and literal[1] == 0x56 and literal[2] == 0x34 and literal[3] == 0x12
  assert literal[12] == 0x78 and literal[15] == 0x12
  assert words.info.registers[1] == wordInfo.registers[1]
  assert words.info.registers[2] == RegisterValue(0x12) and words.info.registers[4] ==
      RegisterValue(128)
  for paid in [false, true]:
    # Bracket a complete four-block charge, a prepaid first block and the next batch's remaining quota.
    for gas in [0'u64, 14, 15, 19, 20, 21, 79, 80, 1000, high(uint64)]:
      # The original path must still stop inside the four-block group when any one source attempt is unaffordable.
      for budget in [0'u64, 1, 4, 5, 19, 20, 21, 39, 40, 41, 79, 80, 81, high(uint64)]:
        var input = wordInfo
        input.blockCharged = paid
        input.gas = MachineGas(gas)
        verifyControl(words, wordProgram, input, budget, [page])
    for budget in 0'u64..83'u64:
      # Every source coordinate remains observable, including partial tails after one or more complete batches.
      var input = wordInfo
      input.blockCharged = paid
      verifyControl(words, wordProgram, input, budget, [page])
  for value in [0'u64, 0x80000000'u64, 0xffffffff'u64, 0xdeadbeef'u64, high(uint64)]:
    # High source bits and sign-extended intermediate byte registers cannot change the final low-word projection.
    for shift in [0'u64, 1'u64, 8'u64, 24'u64, 32'u64, 0xffffffffffffffe0'u64]:
      # Nonaligned shifts decline; an aligned high counter may wrap exactly as four original +8 mutations do.
      var input = wordInfo
      input.registers[1] = RegisterValue(value)
      input.registers[4] = RegisterValue(shift)
      verifyControl(words, wordProgram, input, 100, [page])
  for length in [0'u64, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17]:
    # Opcode171 is !=: a zero/past bound still executes its byte prefix and may continue to the attempt limit.
    for upper in [0'u64, 0x100000000'u64]:
      # Effective memory addresses wrap to32 bits while full-width address/bound registers retain their high bits.
      var input = wordInfo
      input.registers[0] = RegisterValue(65536+upper)
      input.registers[3] = RegisterValue(65536+upper+length)
      verifyControl(words, wordProgram, input, 100, [page])
  for budget in [19'u64, 20, 21, 100]:
    # A behind bound is not an empty != loop: preserve the byte prefix and bounded continuation unchanged.
    var input = wordInfo
    input.registers[3] = RegisterValue(65535)
    verifyControl(words, wordProgram, input, budget, [page])
  for destination in [0, 1, 3, 4]:
    # Prefix-to-store dependence remains intact; only the additional live-role alias prevents word admission.
    let alias = owner([@[198'u8, 0x41, byte(destination)], @[120'u8, byte(destination), 0],
      @[149'u8, 0x00, 1], @[149'u8, 0x44, 8], @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
    var input = wordInfo
    if destination == 0:
      # Admit one initial address-prefix store before a later shifted address enters the protected range.
      input.registers[1] = RegisterValue(65536)
    var actual = newFlatFrame(checkedPlan(alias), [page], input)
    for warm in 0..<6:
      # A previously cached branch must not let a later invalid alias projection bypass the scalar path.
      verifyControl(actual, alias, input, 100, [page])
    for budget in 0'u64..21'u64:
      # Partial aliases preserve the exact operand order around both the old and new batch boundary.
      verifyControl(actual, alias, input, budget, [page])
  let addressData = owner([@[198'u8, 0x40, 2], @[120'u8, 0x02, 0], @[149'u8, 0x00, 1],
    @[149'u8, 0x44, 8], @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
  var addressInfo = wordInfo
  addressInfo.registers[0] = RegisterValue(65791)
  addressInfo.registers[3] = RegisterValue(65807)
  var addressFrame = newFlatFrame(checkedPlan(addressData), [page], addressInfo)
  for warm in 0..<6:
    # An address/data alias changes the next extracted byte across a carry inside the proposed word.
    verifyControl(addressFrame, addressData, addressInfo, 100, [page])
  let carried = pageImage(flatMemorySnapshot(addressFrame), PageIndex(16)).value.bytes
  assert carried[255] == 0xff and carried[256] == 1
  for budget in 0'u64..21'u64:
    # The alias must keep its bytewise source state when the budget reaches a potential bulk entry.
    verifyControl(addressFrame, addressData, addressInfo, budget, [page])
  var wordCrossing = wordInfo
  wordCrossing.registers[0] = RegisterValue(69626)
  wordCrossing.registers[3] = RegisterValue(69642)
  for readonly in [false, true]:
    # A valid two-page word may collapse; a later read-only page must expose the preceding byte prefix before refusal.
    var last = page
    last.index = PageIndex(17)
    if readonly:
      # The first six bytes remain writable even though a later byte of the next group faults.
      last.access = PageAccess.ReadOnly
    assert replaceFlatMemoryChecked(words, [page, last], wordCrossing) == FlatError.None
    for paid in [false, true]:
      # Preserve the first paid block while later batches encounter either gas or the page boundary.
      for gas in [19'u64, 20, 21, 1000]:
        # Full and partial affordable groups must agree on which source attempt reaches the permission boundary.
        for budget in [19'u64, 20, 21, 29, 30, 31, 100]:
          var input = wordCrossing
          input.blockCharged = paid
          input.gas = MachineGas(gas)
          verifyControl(words, wordProgram, input, budget, [page, last])
  assert replaceFlatMemoryChecked(words, [page], wordCrossing) == FlatError.None
  verifyControl(words, wordProgram, wordCrossing, 100, [page])
  assert words.exit == StepExit.Fault and uint64(words.info.pc) == 3
  let partial = pageImage(flatMemorySnapshot(words), PageIndex(16)).value.bytes
  assert partial[4090] == 0x78 and partial[4095] == 0x56
  # Repair after a successful bulk group and later byte fault resumes its already-paid store suffix exactly once.
  let failedWordInfo = words.info
  var repairedFirst = page
  repairedFirst.bytes = partial
  var repairedLast = page
  repairedLast.index = PageIndex(17)
  let repairedWords = [repairedFirst, repairedLast]
  assert replaceFlatMemoryChecked(words, repairedWords, failedWordInfo) == FlatError.None
  verifyControl(words, wordProgram, failedWordInfo, 1, repairedWords)
  assert pageImage(flatMemorySnapshot(words), PageIndex(17)).value.bytes[0] == 0x34
  assert words.info.gas == failedWordInfo.gas and words.info.blockCharged
  assert uint64(words.info.pc) == 6
  verifyControl(words, wordProgram, failedWordInfo, 100, repairedWords)
  var top = page
  top.index = PageIndex(1048575)
  var highInfo = wordInfo
  highInfo.registers[0] = RegisterValue(high(uint64)-16)
  highInfo.registers[3] = RegisterValue(high(uint64))
  assert replaceFlatMemoryChecked(words, [top], highInfo) == FlatError.None
  verifyControl(words, wordProgram, highInfo, 100, [top])
  for immediate in [3'u8, 253'u8]:
    # Encoded positive/negative store offsets affect memory only, preserving the full-width branch register.
    let adjusted = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, immediate], @[149'u8, 0x00, 1],
      @[149'u8, 0x44, 8], @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
    var input = wordInfo
    if immediate == 253:
      # Start three bytes above the mapped base so the negative effective address is valid.
      input.registers[0] = RegisterValue(65539)
      input.registers[3] = RegisterValue(65555)
    var actual = newFlatFrame(checkedPlan(adjusted), [page], input)
    for warm in 0..<6:
      # Each reset validates the new offset through both the cold and subsequently cached word workers.
      verifyControl(actual, adjusted, input, 100, [page])
  var code = takeFlatStream(words)
  var nextWordPage = page
  nextWordPage.index = PageIndex(17)
  var nextWordInfo = wordCrossing
  nextWordInfo.registers[1] = RegisterValue(0xdeadbeef)
  var newWords = newFlatFrame(wordPlan, [page, nextWordPage], nextWordInfo)
  restoreFlatStream(newWords, code)
  verifyControl(newWords, wordProgram, nextWordInfo, 100, [page, nextWordPage])
  let nextFirst = pageImage(flatMemorySnapshot(newWords), PageIndex(16)).value.bytes
  let nextLast = pageImage(flatMemorySnapshot(newWords), PageIndex(17)).value.bytes
  assert nextFirst[4090] == 0xef and nextFirst[4095] == 0xbe and nextLast[0] == 0xad and nextLast[
      9] == 0xde
  assert pageImage(originalWords, PageIndex(16)).value.bytes[0] == 0x78
  let hostedWord = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0], @[149'u8, 0x00, 1],
    @[149'u8, 0x44, 8], @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[10'u8, 7],
    @[40'u8, 0xec, 0xff, 0xff, 0xff]])
  var wordHost = newFlatFrame(checkedPlan(hostedWord), [page], wordInfo)
  verifyControl(wordHost, hostedWord, wordInfo, 100, [page])
  let oldWordObservation = observeFlatHostMemory(wordHost)
  let wordPosterior = writeBytes(oldWordObservation, MemoryAddress(65536), [0xee'u8],
      MemoryByteLimit(1)).value
  let wordPosteriorImages = memoryImages(wordPosterior).value
  var hostRegisters = wordHost.info.registers
  hostRegisters[0] = RegisterValue(65536)
  hostRegisters[1] = RegisterValue(0x1284)
  assert resumeFlatHostMemory(wordHost, wordPosterior, MachineGas(100000), hostRegisters) == StepError.None
  let resumedWordInfo = wordHost.info
  verifyControl(wordHost, hostedWord, resumedWordInfo, 100, wordPosteriorImages)
  let hostWords = pageImage(flatMemorySnapshot(wordHost), PageIndex(16)).value.bytes
  assert hostWords[0] == 0x84 and hostWords[1] == 0x12 and hostWords[15] == 0
  assert pageImage(oldWordObservation, PageIndex(16)).value.bytes[0] == 0x78
  assert pageImage(wordPosterior, PageIndex(16)).value.bytes[0] == 0xee
  checkFlatSource(wordHost, wordPosteriorImages)
  echo "CHECKED_WORD_LOOP_OK"
