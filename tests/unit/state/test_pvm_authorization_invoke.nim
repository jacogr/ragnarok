# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_authorization_invoke_arc_release"}

## Genuine historical authorizers verify fixed invocation inputs, stateless host dispatch, gas and immutable provenance.

import std/[assertions, syncio]
import ../../../src/state/[authorization_invocation, refinement_lookup, store]
import ../../../src/codec/[bounded, composite, work_package, work_digest, work_report]
import ../../../src/pvm/[machine, step, gas, initialize, host_fetch, output]
import ../../../src/chain/parameters
import ../../../src/codec/state_authorization # Invocation names coexist with the existing state codec domain.
import ../../support/[pvm_authorization_invoke, pvm_refinement_outcome, arc_evidence]

# Both public domains remain independently usable when imported into the same module.
let codecDefault = default(AuthorizationResult[int])
let invocationDefault = default(AuthorizationInvocationResult[int])
assert codecDefault.error == AuthorizationError.Uninitialized
assert invocationDefault.error == AuthorizationInvocationError.Uninitialized

let halt = @[50'u8, 0]
let returning = @[refinementImmediate(7, 196608), refinementImmediate(8, 3), halt]
proc check(invocation: AuthorizationInvocation, kind: WorkKind, used: uint64) =
  ## Assert exact consumed gas and source selection; work errors have no successful trace even if guest bytes existed.
  let info = invocation.authorizationInfo.value
  assert info.kind == kind and uint64(info.gasUsed) == used
  assert uint64(info.core) == 0x1234 and uint32(info.host) == 77 and uint32(info.anchor) == 20
  if kind == WorkKind.Success:
    assert info.traceBytes == uint64(invocation.authorizationTrace.value.len)
  else:
    assert info.traceBytes == 0 and invocation.authorizationTrace.error ==
        AuthorizationInvocationError.NotSuccess
let fixture = authorizationFixture(returning)
let first = authorizationRun(fixture).value
check(first, WorkKind.Success, authorizationPrice(fixture))
assert first.authorizationTrace.value == @[21'u8, 22, 23]
let args = authorizationRun(authorizationFixture([halt])).value
assert args.authorizationTrace.value == @[0x34'u8,
    0x12] # Initial r7/r8 select exactly E2(core), without a compact prefix.
for core in [0'u64, 255, 256, 65534]:
  let result = authorizationRun(authorizationFixture([halt]), core = core).value
  assert result.authorizationTrace.value == @[byte(core and 255), byte(core shr 8)]
for core in [65535'u64, 65536, high(uint64)]:
  assert authorizationRun(fixture, core = core).error ==
      AuthorizationInvocationError.InvalidSelection
# Host 0 exposes the fixed gas allowance after its cost and the independently priced guest block.
let gasCode = @[@[10'u8, 0], @[62'u8, 7, 0, 0, 3, 0], refinementImmediate(7, 196608),
  refinementImmediate(8, 8), halt]
let gasFixture = authorizationFixture(gasCode)
let gasResult = authorizationRun(gasFixture).value
let gasUsed = authorizationPrice(gasFixture)+48
check(gasResult, WorkKind.Success, gasUsed)
var remaining = 0'u64
for index, octet in gasResult.authorizationTrace.value: remaining = remaining or (uint64(
    octet) shl (8*index))
assert remaining == 50000000'u64-gasUsed
# Metadata never contributes to the 64000-byte code ceiling; exact-sized code remains executable.
let metadata = authorizationFixture([halt], metadata = newSeq[byte](64000))
assert metadata.preimage.len > 64000
assert authorizationRun(metadata).value.authorizationTrace.value == @[0x34'u8, 0x12]
let exact = authorizationFixture([halt], codeSize = 64000)
assert exact.envelope.len == 64000
assert authorizationRun(exact).value.authorizationInfo.value.kind == WorkKind.Success
let big = authorizationFixture([halt], codeSize = 64001)
var bigCap = default(AuthorizationInvocationLimits)
bigCap.preimage = ByteLimit(200000)
check(authorizationRun(big, bigCap).value, WorkKind.Big,
    0) # BIG needs no CPU, host, execution or output budgets.
let missing = authorizationFixture([halt], missing = true)
check(authorizationRun(missing, default(AuthorizationInvocationLimits)).value, WorkKind.Bad, 0)
assert authorizationRun(authorizationFixture([halt],
    host = 42)).value.authorizationInfo.value.kind == WorkKind.Bad
assert authorizationRun(authorizationFixture([halt],
    anchor = 9)).value.authorizationInfo.value.kind == WorkKind.Bad
assert authorizationRun(authorizationFixture([halt],
    anchor = 10)).value.authorizationInfo.value.kind == WorkKind.Success
# Fetch exposes only parameters/package fields; configuration/token/payload distinguish all raw blob selections.
proc fetchCode(selector: uint64, size: uint64): seq[seq[byte]] =
  ## Actual guest fetch calls use zero offset and item zero, returning only copied data from the original package.
  @[refinementImmediate(7, 196608), refinementImmediate(8, 0), refinementImmediate(9, size),
    refinementImmediate(10, selector), refinementImmediate(11, 0), @[10'u8, 2],
    refinementImmediate(7, 196608), refinementImmediate(8, size), halt]
for selector in [0'u64, 7, 8, 9, 13]:
  let size = if selector == 9: 1'u64 elif selector in [8'u64, 13]: 2'u64 else: 3'u64
  let done = authorizationRun(authorizationFixture(fetchCode(selector, size))).value
  let expected = if selector == 0: @[255'u8, 255, 255] elif selector == 7: @[77'u8, 0, 0]
    elif selector == 8: @[81'u8, 82] elif selector == 9: @[91'u8] else: @[31'u8, 32]
  assert done.authorizationTrace.value == expected
# Psi_I itself accepts traces above the report budget; later report composition must apply its own 49152-byte gate.
let longSource = authorizationFixture([refinementImmediate(7, 196608), refinementImmediate(8,
    49153), halt], codeSize = 64000)
let longTrace = authorizationRun(longSource).value
assert longTrace.authorizationInfo.value.kind == WorkKind.Success
assert longTrace.authorizationTrace.value.len == 49153 and longTrace.authorizationTrace.value[0] == 21
var longCap = authorizationLimits()
longCap.output = OutputByteLimit(49152)
assert authorizationRun(longSource, longCap).error == AuthorizationInvocationError.LimitExceeded
# Absent entropy, trace, external inputs/current item and accumulation operands return NONE, not empty present data.
for selector in [1'u64, 2, 3, 4, 5, 6, 14, 15, 16]:
  let code = @[refinementImmediate(7, high(uint64)), refinementImmediate(9, 0),
    refinementImmediate(10, selector), @[10'u8, 2], @[62'u8, 7, 0, 0, 3, 0],
    refinementImmediate(7, 196608), refinementImmediate(8, 8), halt]
  assert authorizationRun(authorizationFixture(code)).value.authorizationTrace.value ==
    @[255'u8, 255, 255, 255, 255, 255, 255, 255]
for host in [7'u8, 8, 9, 13, 14, 15, 27, 99]:
  let code = @[@[10'u8, host], @[62'u8, 7, 0, 0, 3, 0], refinementImmediate(7, 196608),
    refinementImmediate(8, 8), halt]
  let source = authorizationFixture(code)
  let done = authorizationRun(source).value
  check(done, WorkKind.Success, authorizationPrice(source)+1000)
  assert done.authorizationTrace.value == @[254'u8, 255, 255, 255, 255, 255, 255, 255]
# Heap geometry comes from the standard envelope, with exact adopted shared host pricing and local page refusal.
let heapCode = @[refinementImmediate(7, 50), @[10'u8, 1], @[62'u8, 7, 0, 0, 3, 0],
  refinementImmediate(7, 196608), refinementImmediate(8, 1), halt]
let heap = authorizationFixture(heapCode)
let grown = authorizationRun(heap).value
check(grown, WorkKind.Success, authorizationPrice(heap)+396)
assert grown.authorizationTrace.value == @[50'u8]
var cap = authorizationLimits()
cap.initialization.pages = PageLimit(3)
let heapRefused = authorizationRun(heap, cap)
assert heapRefused.error == AuthorizationInvocationError.HostFailure and heapRefused.hostError ==
    AuthorizationHostError.LimitExceeded
# Psi_M halt readability and guest panic/fault do not become local output-copy failures.
for pointer in [65536'u64, 69631, high(uint64)]:
  let source = authorizationFixture([refinementImmediate(7, pointer), refinementImmediate(8, 3), halt])
  cap = authorizationLimits()
  cap.output = OutputByteLimit(if pointer == 65536: 3'u64 else: 0'u64)
  let done = authorizationRun(source, cap).value
  check(done, WorkKind.Success, authorizationPrice(source))
  assert done.authorizationTrace.value == (if pointer == 65536: @[11'u8, 12, 13] else: newSeq[byte]())
for ending in [@[0'u8], @[52'u8, 7, 0, 0, 0, 1]]:
  let source = authorizationFixture([ending, halt])
  check(authorizationRun(source).value, WorkKind.Panic, authorizationPrice(source))
# Requested-length charging occurs even for absent trace; huge requests yield exact saturated guest OOG.
let debt = authorizationFixture([refinementImmediate(9, high(uint64)), refinementImmediate(10, 2),
    @[10'u8, 2], halt])
check(authorizationRun(debt).value, WorkKind.OutOfGas, 50000000)
# Spend all but one credit on an absent fetch, then enter a new unaffordable block: instruction OOG preserves that credit.
var oogCode = @[refinementImmediate(9, 0), refinementImmediate(10, 2), @[10'u8, 2], @[40'u8, 2],
  refinementImmediate(7, 1), refinementImmediate(8, 2), halt]
let firstPrice = authorizationPrice(authorizationFixture(oogCode))
let charged = 50000000'u64-firstPrice-80-1
let requested = charged*32 div 3 # ceil(96*z/1024) equals charged for this exact constructed natural.
oogCode[0] = refinementImmediate(9, requested)
check(authorizationRun(authorizationFixture(oogCode)).value, WorkKind.OutOfGas, 49999999)
# All preparation stages retain typed local reasons; no partial trace/CPU/gas escapes local policy failures.
assert authorizationRun(default(AuthorizationFixture)).error ==
    AuthorizationInvocationError.InvalidParameters
assert runAuthorizationInvocation(fixture.state, default(OwnedWorkPackage), CoreIndex(0),
    fixture.parameters,
  authorizationLimits()).error == AuthorizationInvocationError.InvalidSelection
assert authorizationRun(authorizationFixture([halt], wrongHash = true)).error ==
    AuthorizationInvocationError.InvalidState
assert authorizationRun(authorizationFixture([halt], overrideBytes = @[128'u8])).error ==
    AuthorizationInvocationError.MalformedCode
let malformed = authorizationRun(authorizationFixture([halt], overrideBytes = @[0'u8, 1]))
assert malformed.error == AuthorizationInvocationError.InitializationFailure and
    malformed.initializationError == InitializationError.InvalidEnvelope
let lookup = authorizationRun(authorizationFixture([halt], malformedState = true))
assert lookup.error == AuthorizationInvocationError.LookupFailure and lookup.lookupError ==
    HistoricalLookupError.MalformedState
for policy in 0..<8:
  cap = authorizationLimits()
  case policy
  of 0: cap.preimage = ByteLimit(0)
  of 1: cap.initialization.envelope = InitializationByteLimit(0)
  of 2: cap.initialization.pages = PageLimit(0)
  of 3: cap.encoding = FetchEncodingLimit(0)
  of 4: cap.package = FetchPackageLimit(0)
  of 5: cap.steps = ExecutionStepLimit(0)
  of 6: cap.cycles = GasCycleLimit(0)
  else: cap.output = OutputByteLimit(2)
  let refused = authorizationRun(fixture, cap)
  let expected = if policy in [0, 1, 7]: AuthorizationInvocationError.LimitExceeded
    elif policy == 2: AuthorizationInvocationError.InitializationFailure
    elif policy in [3, 4]: AuthorizationInvocationError.FetchFailure else: AuthorizationInvocationError.ExecutionFailure
  assert refused.error == expected
cap = authorizationLimits()
cap.copy = MemoryByteLimit(1)
let copyRefused = authorizationRun(authorizationFixture(fetchCode(8, 2)), cap)
assert copyRefused.error == AuthorizationInvocationError.HostFailure and copyRefused.hostError ==
    AuthorizationHostError.LimitExceeded
cap = authorizationLimits()
cap.calls = HostCallLimit(0)
let callRefused = authorizationRun(gasFixture, cap)
assert callRefused.error == AuthorizationInvocationError.ExecutionFailure
assert callRefused.executionError == StepError.HostCallLimitExceeded
# Saved source ownership, copied metadata/bytes and independent replay cannot replace the invocation's original trace or code.
var trace = first.authorizationTrace.value
trace[0] = 255
var info = first.authorizationInfo.value
info.kind = WorkKind.Bad
assert first.authorizationTrace.value == @[21'u8, 22, 23]
let replay = runAuthorizationInvocation(first.authorizationState.value,
  first.authorizationPackage.value,
  first.authorizationInfo.value.core, first.authorizationParameters.value, authorizationLimits()).value
assert replay.authorizationTrace.value == first.authorizationTrace.value
assert default(AuthorizationInvocation).authorizationInfo.error ==
    AuthorizationInvocationError.Uninitialized
assert default(AuthorizationInvocation).authorizationPackage.error ==
    AuthorizationInvocationError.Uninitialized
assert default(AuthorizationInvocation).authorizationState.error ==
    AuthorizationInvocationError.Uninitialized
assert default(AuthorizationInvocation).authorizationParameters.error ==
    AuthorizationInvocationError.Uninitialized
assert default(AuthorizationInvocation).authorizationTrace.error ==
    AuthorizationInvocationError.Uninitialized
proc detached(): AuthorizationInvocation =
  ## Retain complete source provenance after all original caller fixture handles leave scope.
  authorizationRun(authorizationFixture(returning)).value
let retained = detached()
assert retained.authorizationTrace.value == @[21'u8, 22, 23]
assert uint32(retained.authorizationPackage.value.workPackageInfo.value.host) == 77
assert runAuthorizationInvocation(retained.authorizationState.value,
  retained.authorizationPackage.value,
  retained.authorizationInfo.value.core, retained.authorizationParameters.value,
  authorizationLimits()).value.authorizationTrace.value == @[21'u8, 22, 23]
proc cycle() =
  ## Fresh original maps/code/packages and success/local-refusal owners all retire before the next allocation observation.
  let source = authorizationFixture(returning)
  let result = authorizationRun(source).value
  assert result.authorizationTrace.value == @[21'u8, 22, 23]
  var limited = authorizationLimits()
  limited.output = OutputByteLimit(2)
  assert authorizationRun(source, limited).error == AuthorizationInvocationError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_authorization_invoke", 1000, before, after)
echo "PVM authorization invoke passed"
echo "ARC_RELEASE cycles=1000 unchanged"
