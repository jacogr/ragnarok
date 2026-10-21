# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_refinement_bootstrap_arc_release"}

## Literal code/package hashes and argument bytes verify historical code binding and entry-zero bootstrap.

import std/[assertions, syncio]
import ../../../src/state/[refinement_bootstrap, refinement_dispatch, store]
import ../../../src/pvm/[initialize, machine, program, step, gas, host_fetch, refinement_exports, output]
import ../../../src/chain/parameters
import ../../../src/crypto/primitives
import ../../../src/codec/[bounded, composite, natural, work_package, work_report, work_digest,
  state_accounts, state_layout, state_service_values, state_requests, state_trie]
import ../../support/arc_evidence

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Frozen Python hashlib.blake2b(digest_size=32) oracles over independently laid-out literal GP bytes.
let expectedCodeHash = [141'u8, 7, 23, 157, 74, 113, 205, 19, 174, 74, 148, 253, 84, 241, 255, 131,
    4, 138, 27, 199, 83, 20, 219, 31, 109, 106, 75, 71, 2, 228, 130, 69]
let expectedPackageHash = [104'u8, 28, 198, 148, 93, 64, 58, 159, 54, 228, 209, 164, 133, 150, 116,
    88, 193, 253, 87, 28, 38, 162, 102, 218, 222, 165, 216, 34, 202, 241, 116, 77]

proc parameters(): Parameters =
  ## Literal field maxima provide a valid immutable profile while all protocol code gates remain fixed.
  var wire = default(array[122, byte])
  for index in 0..<122: wire[index] = 255
  decodeParameters(wire).value
proc code(exporting = false): seq[byte] =
  ## E(var metadata=[201,202]) followed by a literal standard envelope and halt/export raw program.
  result = @[2'u8, 201, 202]
  for index in 0..<11: result.add(0) # Empty RO/RW/extra heap/stack fields, without a variable outer envelope length.
  let raw = if exporting: @[0'u8, 0, 4, 10, 8, 50, 0, 5] else: @[0'u8, 0, 2, 50, 0, 1]
  result.add(byte(raw.len))
  for index in 0..<3: result.add(0) # E4 raw-program length.
  for octet in raw: result.add(octet)
proc package(hash: array[32, byte], anchor = 20'u32, payload = @[81'u8, 82, 83]): OwnedWorkPackage =
  ## A two-item package makes service, gas and payload selection independently visible.
  let source = WorkPackage(context: RefinementContext(lookupSlot: LookupSlot(anchor)),
    authorization: @[71'u8], configuration: @[61'u8, 62], items: @[
      WorkItem(service: ServiceIndex(42), codeHash: CodeHash(hash), refineGas: Gas(10000),
          payload: payload),
      WorkItem(service: ServiceIndex(99), codeHash: CodeHash(hash), refineGas: Gas(20000),
          payload: @[91'u8])])
  var wire = newSeq[byte](2048)
  let config = fullPackageConfig(ByteLimit(2048))
  let size = encodeWorkPackage(source, config, wire).value
  decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
proc state(raw: seq[byte], hash: array[32, byte], damage = 0): StateStoreSnapshot =
  ## Deliberately unrelated current account code hashes prove Psi_R selects the work item's historical code.
  var entries: seq[StateEntry] = @[]
  for service in [42'u32, 99]:
    if damage != 1:
      entries.add(serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(), ByteLimit(89)).value)
    if damage != 2:
      entries.add(servicePreimageEntry(ServiceIndex(service), ServicePreimageHash(hash), raw,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(raw.len)))).value)
    if damage != 3:
      let key = serviceRequestKey(ServiceIndex(service), ServicePreimageHash(hash), RequestLength(
          uint32(raw.len)), ByteLimit(32)).value
      entries.add(StateEntry(key: key, value: if damage == 4: @[0'u8] else: @[1'u8, 10, 0, 0,
          0])) # Literal history is independent of the decoder.
  newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(8),
    perValue: ByteLimit(5000000), totalValueBytes: ByteLimit(10000000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(8), writeValueBytes: ByteLimit(10000000))).value.snapshot.value
proc limits(): RefinementBootstrapLimits =
  ## Capture all small fixture data with independent exact CPU/page bounds.
  RefinementBootstrapLimits(preimage: ByteLimit(4000000), package: ByteLimit(2048),
    arguments: ByteLimit(512), initialization: InitializationLimits(
        envelope: InitializationByteLimit(64),
      program: ProgramByteLimit(32), jumps: JumpCountLimit(0), pages: PageLimit(1)))
proc prepare(raw = code(), anchor = 20'u32, damage = 0, item = 0'u64, core = 5'u64,
    cap = limits(), payload = @[81'u8, 82, 83]): RefinementBootstrapResult[
        PreparedRefinementBootstrap] =
  ## Sources are temporary; the returned owner must retain every input needed for host capture and replay.
  let hash = array[32, byte](blake2b256(raw).value)
  prepareRefinementBootstrap(state(raw, hash, damage), package(hash, anchor, payload),
      FetchItemIndex(item),
    CoreIndex(core), parameters(), cap)
proc hostLimits(): RefinementCaptureLimits =
  ## Present empty input tables still carry both package item rows.
  RefinementCaptureLimits(trace: FetchTraceLimit(0), package: FetchPackageLimit(16),
    encoding: FetchEncodingLimit(2048), inputs: FetchInputLimit(0))
proc hosts(prepared: PreparedRefinementBootstrap): RefinementBootstrapResult[
    PreparedRefinementExecution] =
  ## Bind the ready owner's private original CPU and provenance without replacement arguments.
  prepared.bootstrapHosts([], RefinementInputs(extrinsics: @[newSeq[seq[byte]](), newSeq[seq[byte]](
    )], imports: @[newSeq[FetchSegment](), newSeq[FetchSegment]()]),
    ExportOffset(7), hostLimits())
proc run(prepared: PreparedRefinementExecution): RefinementDispatchResult[RefinementOutcome] =
  ## Bound the raw run independently of capture, code and argument policies.
  executeRefinement(prepared, MemoryByteLimit(64), ExportLimits(items: ElementLimit(1),
      bytes: ByteLimit(4104)),
    ExecutionStepLimit(4), HostCallLimit(1), GasCycleLimit(1000))

let raw = code()
assert raw.len == 24 and array[32, byte](blake2b256(raw).value) == expectedCodeHash
let prepared = prepare().value
let facts = prepared.bootstrapInfo.value
assert facts.status == RefinementCodeStatus.Ready and facts.preimageBytes == 24
assert uint32(facts.service) == 42 and uint64(facts.gas) == 10000 and uint32(facts.anchor) == 20
assert prepared.bootstrapPackageHash.value.bytes == expectedPackageHash
var expected = @[5'u8, 0, 42, 3, 81, 82, 83]
for octet in expectedPackageHash: expected.add(octet) # Raw hash follows payload, without a length/tag/domain byte.
assert prepared.bootstrapArguments.value == expected
let initial = prepared.bootstrapMachine.value
let cpu = initial.machineInfo.value
assert uint64(cpu.pc) == 0 and uint64(cpu.gas) == 10000 and not cpu.blockCharged
assert uint64(cpu.registers[7]) == 0xfeff0000'u64 and uint64(cpu.registers[8]) == 39
assert readBytes(initial.memoryOf.value, MemoryAddress(0xfeff0000'u64), MemoryLength(39),
    MemoryByteLimit(39)).value == expected
let done = run(hosts(prepared).value).value
assert done.outcome.exit == StepExit.Halt and uint64(done.exports.count) == 0
assert captureOutput(done.outcome, OutputByteLimit(39)).value == expected
# Compact core/payload framing and the second work item's gas/service remain distinct.
let other = prepare(item = 1).value
assert uint32(other.bootstrapInfo.value.service) == 99 and uint64(other.bootstrapInfo.value.gas) == 20000
assert other.bootstrapArguments.value[0..4] == @[5'u8, 1, 99, 1, 91]
let compact = prepare(core = 128).value
assert compact.bootstrapArguments.value[0..7] == @[128'u8, 128, 0, 42, 3, 81, 82, 83]
let largePayload = prepare(payload = newSeq[byte](130)).value
assert largePayload.bootstrapArguments.value[0..4] == @[5'u8, 0, 42, 128, 130]
# Metadata cannot bypass the entire-preimage BIG gate, and BIG requires no local preimage copy allowance.
var oversized = newSeq[byte](4000001)
var cap = limits()
cap.preimage = ByteLimit(0)
let big = prepare(oversized, cap = cap).value
assert big.bootstrapInfo.value.status == RefinementCodeStatus.Big
assert big.bootstrapMachine.error == RefinementBootstrapError.NotReady
assert big.bootstrapArguments.error == RefinementBootstrapError.NotReady
assert hosts(big).error == RefinementBootstrapError.NotReady
# Exactly four million bytes, mostly metadata, remains eligible; only the authenticated code suffix initializes.
let metadata = natural.encode(JamNatural(3999975))
assert metadata.len == 4
var exact: seq[byte] = @[]
for index in 0..<metadata.len: exact.add(metadata.bytes[index])
for index in 0..<3999975: exact.add(0)
for index in 3..<raw.len: exact.add(raw[index])
assert exact.len == 4000000
let boundary = prepare(exact).value
assert boundary.bootstrapInfo.value.status == RefinementCodeStatus.Ready
assert boundary.bootstrapArguments.value.len == 39
# Absent account/preimage/history availability selects BAD without executable bytes, even under a zero copy cap.
for damage in [1, 2, 4]:
  let bad = prepare(damage = damage, cap = cap).value
  assert bad.bootstrapInfo.value.status == RefinementCodeStatus.Bad
  assert bad.bootstrapMachine.error == RefinementBootstrapError.NotReady
  assert bad.bootstrapArguments.error == RefinementBootstrapError.NotReady
  assert bad.bootstrapPackageHash.error == RefinementBootstrapError.NotReady
assert prepare(anchor = 9).value.bootstrapInfo.value.status == RefinementCodeStatus.Bad
assert prepare(damage = 3).error == RefinementBootstrapError.MalformedState
# Invalid metadata is a local gate; malformed JAM framing/programs never become a ready CPU or fabricated BAD.
for malformed in [newSeq[byte](), @[1'u8], @[128'u8, 0]]:
  assert prepare(malformed).error == RefinementBootstrapError.MalformedCode
assert prepare(@[0'u8]).error == RefinementBootstrapError.InvalidEnvelope
var invalid = raw
invalid[invalid.len-1] = 0 # No instruction start bit, despite a correctly hashed preimage and valid envelope framing.
assert prepare(invalid).error == RefinementBootstrapError.InvalidProgram
# Real historical lookup and hashing cannot promote final missing successors to a ready refinement CPU.
for program in [@[0'u8, 0, 4, 51, 7, 7, 1, 9],
    @[0'u8, 0, 6, 51, 7, 7, 170, 0, 253, 9]]:
  var authenticated = @[2'u8, 201, 202]
  for index in 0..<11: authenticated.add(0)
  authenticated.add(byte(program.len))
  for index in 0..<3: authenticated.add(0)
  for octet in program: authenticated.add(octet)
  let source = authenticated
  assert prepare(authenticated).error == RefinementBootstrapError.InvalidProgram
  assert authenticated == source
  authenticated[18] = 0 # An unreachable final successor is still a whole-module defect.
  assert prepare(authenticated).error == RefinementBootstrapError.InvalidProgram
# A present successor produces a Ready owner rather than a preparation failure.
block:
  var authenticated = @[2'u8, 201, 202]
  for index in 0..<11: authenticated.add(0)
  for octet in [9'u8, 0, 0, 0, 0, 0, 5, 51, 7, 7, 1, 0, 25]: authenticated.add(octet)
  assert prepare(authenticated).value.bootstrapInfo.value.status == RefinementCodeStatus.Ready

# A wrong committed preimage hash is invalid supplied state; backend failures cannot fabricate BAD/Ready/hash bytes.
let originalState = state(raw, expectedCodeHash)
var altered = raw
altered[1] = 255
let inconsistent = state(altered, expectedCodeHash)
let pkg = package(expectedCodeHash)
assert prepareRefinementBootstrap(inconsistent, pkg, FetchItemIndex(0), CoreIndex(5), parameters(),
    limits()).error == RefinementBootstrapError.InvalidState
for successes in 0..3:
  failAfter(cint(successes)) # preimage key, request key, code content digest, canonical package digest.
  assert prepareRefinementBootstrap(originalState, pkg, FetchItemIndex(0), CoreIndex(5), parameters(
    ), limits()).error == RefinementBootstrapError.BackendFailure
  failHash(0)
# Full-width selections and independent local capture/initialization policies refuse before unsafe narrowing or publication.
assert prepare(item = high(uint64)).error == RefinementBootstrapError.InvalidSelection
assert prepare(core = high(uint64)).error == RefinementBootstrapError.InvalidSelection
for policy in 0..<6:
  var limited = limits()
  case policy
  of 0: limited.preimage = ByteLimit(23)
  of 1: limited.package = ByteLimit(328)
  of 2: limited.arguments = ByteLimit(38)
  of 3: limited.initialization.envelope = InitializationByteLimit(20)
  of 4: limited.initialization.program = ProgramByteLimit(5)
  else: limited.initialization.pages = PageLimit(0)
  assert prepare(cap = limited).error == RefinementBootstrapError.LimitExceeded
var precise = limits()
precise.preimage = ByteLimit(24)
precise.package = ByteLimit(329)
precise.arguments = ByteLimit(39)
precise.initialization.envelope = InitializationByteLimit(21)
precise.initialization.program = ProgramByteLimit(6)
assert prepare(cap = precise).error == RefinementBootstrapError.None
assert prepareRefinementBootstrap(default(StateStoreSnapshot), pkg, FetchItemIndex(0), CoreIndex(5),
    parameters(), limits()).error == RefinementBootstrapError.InvalidState
assert prepareRefinementBootstrap(originalState, default(OwnedWorkPackage), FetchItemIndex(0),
    CoreIndex(5), parameters(), limits()).error == RefinementBootstrapError.InvalidSelection
assert prepareRefinementBootstrap(originalState, pkg, FetchItemIndex(0), CoreIndex(5), default(
    Parameters), limits()).error == RefinementBootstrapError.InvalidParameters
assert default(PreparedRefinementBootstrap).bootstrapInfo.error ==
    RefinementBootstrapError.Uninitialized
# Caller changes to extracted arguments cannot alter later extraction, original CPU memory or bound host capture.
var changed = prepared.bootstrapArguments.value
changed[0] = 255
assert prepared.bootstrapArguments.value == expected
assert captureOutput(run(hosts(prepared).value).value.outcome, OutputByteLimit(39)).value == expected
let exporting = prepare(code(true)).value
let exported = run(hosts(exporting).value).value
assert exported.outcome.exit == StepExit.Halt and uint64(exported.exports.count) == 1
let segment = array[4104, byte](exported.exports.segment(ExportCount(0)))
let arguments = exporting.bootstrapArguments.value
for index in 0..<arguments.len: assert segment[index] == arguments[index]
for index in arguments.len..<4104: assert segment[index] == 0
# Nonzero RO/RW/extra-heap/stack fields bind the adopted heap geometry to the authenticated envelope.
var geometry = @[2'u8, 201, 202, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 201, 211]
let heapRaw = @[0'u8, 0, 14, 20, 7, 193, 239, 15, 0, 0, 0, 0, 0, 10, 1, 50, 0, 1, 20]
geometry.add(byte(heapRaw.len))
for index in 0..<3: geometry.add(0) # Complete E4 raw-program extent before the independently authored instruction bytes.
for octet in heapRaw: geometry.add(octet)
var geometryLimits = limits()
geometryLimits.initialization.pages = PageLimit(5)
let geometryBootstrap = prepare(geometry, cap = geometryLimits).value
let geometryRun = run(hosts(geometryBootstrap).value).value
assert geometryRun.outcome.exit == StepExit.Halt
assert uint64(geometryRun.outcome.machine.machineInfo.value.registers[7]) == 50,
  "RO selects heap page 48; RW plus extra page return 50; a request above zone-rounded stack ceiling cannot grow"
# Fresh source maps, ready owners, temporary captures and failed scratch allocations all retire at each cycle.
proc cycle() =
  ## Construct real fresh provenance, then exercise both complete execution and a refused argument budget.
  let fresh = prepare().value
  assert run(hosts(fresh).value).value.outcome.exit == StepExit.Halt
  var limited = limits()
  limited.arguments = ByteLimit(0)
  assert prepare(cap = limited).error == RefinementBootstrapError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_refinement_bootstrap", 1000, before, after)
echo "PVM refinement bootstrap passed"
echo "ARC_RELEASE cycles=1000 unchanged"
