# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original test-only bound refinement fixtures for outcome witnesses and strict API misuse probes.
## Exposes authored programs, temporary complete maps, finite policies and empty manifest-matching input rows.

import std/assertions
import ../../src/state/[refinement_bootstrap, refinement_outcome, refinement_dispatch, store]
import ../../src/pvm/[machine, program, initialize, gas, step, host_fetch, refinement_exports, output]
import ../../src/codec/[bounded, composite, state_accounts, state_service_values, state_requests,
  state_trie, work_package, work_report, work_digest]
import ../../src/chain/parameters
import ../../src/crypto/primitives

proc refinementImmediate*(register: byte, value: uint64): seq[byte] =
  ## Independent load_imm_64 encoding preserves every high address/value bit.
  result = @[20'u8, register]
  for index in 0..<8: result.add(byte((value shr (8*index)) and 255))
proc refinementInputs*(): RefinementInputs =
  ## One actual package item has no extrinsic or imported-segment manifests.
  RefinementInputs(extrinsics: @[newSeq[seq[byte]]()], imports: @[newSeq[FetchSegment]()])
proc refinementLimits*(): RefinementInvocationLimits =
  ## Every policy is finite and independent; tests lower one cap without changing protocol gas or output kind.
  RefinementInvocationLimits(capture: RefinementCaptureLimits(trace: FetchTraceLimit(0),
    package: FetchPackageLimit(16), encoding: FetchEncodingLimit(4096), inputs: FetchInputLimit(0)),
    copy: MemoryByteLimit(512), exports: ExportLimits(items: ElementLimit(2), bytes: ByteLimit(8208)),
    steps: ExecutionStepLimit(32), calls: HostCallLimit(4), cycles: GasCycleLimit(1000),
    output: OutputByteLimit(512))
proc refinementFixture*(instructions: openArray[seq[byte]], credit = 10000'u64,
    missing = false, oversized = false, pages = 3'u32,
    writable: seq[byte] = @[21'u8, 22, 23]): PreparedRefinementBootstrap =
  ## Build one original standard envelope with distinguishable RO/RW prefixes and genuine code commitments.
  ## Sources die before extraction; the bootstrap owns complete state/package/code/arguments independently.
  var code: seq[byte] = @[]
  var starts: seq[bool] = @[]
  for instruction in instructions:
    assert instruction.len > 0
    for index, octet in instruction:
      code.add(octet)
      starts.add(index == 0) # Only actual instruction starts enter the independently assembled mask.
  assert code.len > 0 and code.len < 128
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index, marked in starts:
    if marked: mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: raw.add(octet)
  assert writable.len <= 4096 # Keep the test envelope's writable fixture within one page.
  var preimage = @[0'u8, 3, 0, 0, byte(writable.len and 255), byte(writable.len shr 8),
    0, 0, 0, 0, 0, 0, 11, 12, 13]
  for octet in writable: preimage.add(octet) # Literal guest programs can now be captured through the real bootstrap.
  preimage.add(byte(raw.len))
  for index in 0..<3: preimage.add(0) # E4 raw-program length follows the fixed RO/RW bytes.
  for octet in raw: preimage.add(octet)
  if oversized: preimage = newSeq[byte](4000001) # BIG is selected before metadata/program parsing or bounded copying.
  let hash = array[32, byte](blake2b256(preimage).value)
  var entries: seq[StateEntry] = @[]
  if not missing:
    entries.add(serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(), ByteLimit(
        ServiceMetadataBytes)).value)
    entries.add(servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), preimage,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(
          preimage.len)))).value)
    let key = serviceRequestKey(ServiceIndex(42), ServicePreimageHash(hash),
      RequestLength(uint32(preimage.len)), ByteLimit(32)).value
    entries.add(StateEntry(key: key, value: @[1'u8, 10, 0, 0,
        0])) # Literal historical availability at package anchor twenty.
  let state = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4),
    perValue: ByteLimit(5000000), totalValueBytes: ByteLimit(5001000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(5001000))).value.snapshot.value
  let source = WorkPackage(context: RefinementContext(lookupSlot: LookupSlot(20)),
    items: @[WorkItem(service: ServiceIndex(42), codeHash: CodeHash(hash), refineGas: Gas(credit),
      payload: @[81'u8, 82, 83])])
  var wire = default(array[4096, byte])
  let config = fullPackageConfig(ByteLimit(4096))
  let size = encodeWorkPackage(source, config, wire).value
  let package = decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
  var parameterBytes = default(array[122, byte])
  for index in 0..<122: parameterBytes[index] = 255 # A valid fixed parameter snapshot with wide core bounds.
  let parameters = decodeParameters(parameterBytes).value
  prepareRefinementBootstrap(state, package, FetchItemIndex(0), CoreIndex(5), parameters,
    RefinementBootstrapLimits(preimage: ByteLimit(4000000), package: ByteLimit(4096),
        arguments: ByteLimit(64),
      initialization: InitializationLimits(envelope: InitializationByteLimit(512),
          program: ProgramByteLimit(160),
        jumps: JumpCountLimit(0), pages: PageLimit(pages)))).value
proc refinementPrice*(bootstrap: PreparedRefinementBootstrap): uint64 =
  ## Reuse the separately verified gas component for block pricing; host prices/normalization expectations are literal.
  let cpu = bootstrap.bootstrapMachine.value
  uint64(blockGas(cpu.programOf.value, CodeAddress(0), GasCycleLimit(1000)).value)
