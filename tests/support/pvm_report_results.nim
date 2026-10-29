# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original multi-item package/state fixtures exercise ordered report rules through actual guest execution.

import std/assertions
import ../../src/state/refinement/[report as refinement_report, bootstrap as refinement_bootstrap,
    outcome as refinement_outcome, dispatch as refinement_dispatch]
import ../../src/state/store
import ../../src/pvm/[machine, program, initialize, host_fetch, refinement_exports]
import ../../src/codec/[bounded, composite]
import ../../src/codec/work/[package as work_package, digest as work_digest, report as work_report]
import ../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    requests as state_requests, trie as state_trie]
import ../../src/chain/parameters
import ../../src/crypto/primitives
import ./pvm_refinement_outcome

type
  ReportGuest* = object ## Test-only authored guest with independent protocol declaration and eligibility selection.
    instructions*: seq[seq[byte]]
    declared*: uint64
    credit*: uint64
    missing*, oversized*: bool
    writable*: seq[byte]
  ReportFixture* = object ## Original immutable owners permit replay, source lifetime and late-failure witnesses.
    state*: StateStoreSnapshot
    package*: OwnedWorkPackage
    parameters*: Parameters
    inputs*: RefinementInputs

proc reportGuest*(instructions: openArray[seq[byte]], declared = 0'u64,
    credit = 10000'u64, missing = false, oversized = false): ReportGuest =
  ## Copy authored instruction rows; every guest starts with distinguishable writable bytes.
  result = ReportGuest(declared: declared, credit: credit, missing: missing,
    oversized: oversized, writable: @[21'u8, 22, 23])
  for instruction in instructions: result.instructions.add(instruction)
proc appendGuest(guest: ReportGuest, service: ServiceIndex, entries: var seq[
    StateEntry]): WorkItem =
  ## Build original standard code and literal availability records for a distinct service per package item.
  var code: seq[byte] = @[]
  var starts: seq[bool] = @[]
  for instruction in guest.instructions:
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
  assert guest.writable.len <= 65535 # Bound the independently encoded two-byte writable extent.
  var preimage = @[0'u8, 3, 0, 0, byte(guest.writable.len and 255), byte(guest.writable.len shr 8),
    0, 0, 0, 0, 0, 0, 11, 12, 13]
  for octet in guest.writable: preimage.add(octet) # Literal guest programs can now be captured through the real bootstrap.
  preimage.add(byte(raw.len))
  for index in 0..<3: preimage.add(0) # E4 raw-program length follows the fixed RO/RW bytes.
  for octet in raw: preimage.add(octet)
  if guest.oversized: preimage = newSeq[byte](4000001) # BIG is selected before metadata/program parsing or bounded copying.
  let hash = array[32, byte](blake2b256(preimage).value)
  if not guest.missing:
    entries.add(serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(
        ServiceMetadataBytes)).value)
    entries.add(servicePreimageEntry(service, ServicePreimageHash(hash), preimage,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(
          preimage.len)))).value)
    let key = serviceRequestKey(service, ServicePreimageHash(hash),
      RequestLength(uint32(preimage.len)), ByteLimit(32)).value
    entries.add(StateEntry(key: key, value: @[1'u8, 10, 0, 0,
        0])) # Literal historical availability at package anchor twenty.
  WorkItem(service: service, codeHash: CodeHash(hash), refineGas: Gas(guest.credit),
    accumulateGas: Gas(100), exports: ExportCount(guest.declared), payload: @[81'u8, byte(uint32(service))])
proc reportFixture*(guests: openArray[ReportGuest]): ReportFixture =
  ## Capture complete state and canonical package snapshots; mutable sources retire before callers execute.
  result = default(ReportFixture)
  var entries: seq[StateEntry] = @[]
  var source = WorkPackage(context: RefinementContext(lookupSlot: LookupSlot(20)))
  for index, guest in guests:
    source.items.add(appendGuest(guest, ServiceIndex(uint32(42+index)), entries))
    result.inputs.extrinsics.add(newSeq[seq[byte]]())
    result.inputs.imports.add(newSeq[FetchSegment]()) # All actual manifests are empty and package-aligned.
  result.state = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(48),
    perValue: ByteLimit(5000000), totalValueBytes: ByteLimit(80000000), nodes: TrieNodeLimit(
        10000)),
    writes: ElementLimit(48), writeValueBytes: ByteLimit(80000000))).value.snapshot.value
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let size = encodeWorkPackage(source, config, wire).value
  result.package = decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
  var parameterBytes = default(array[122, byte])
  for index in 0..<122: parameterBytes[index] = 255 # Valid wide bounds match the shared refinement fixtures.
  result.parameters = decodeParameters(parameterBytes).value
proc reportLimits*(): RefinementReportLimits =
  ## Separate local policies admit protocol boundary tests while bounding every invocation and aggregate owner.
  result = RefinementReportLimits(items: ElementLimit(16), exports: ElementLimit(3072),
    blobs: ByteLimit(49152), bootstrap: RefinementBootstrapLimits(preimage: ByteLimit(4000000),
      package: ByteLimit(4096), arguments: ByteLimit(64), initialization: InitializationLimits(
      envelope: InitializationByteLimit(512), program: ProgramByteLimit(160),
      jumps: JumpCountLimit(0), pages: PageLimit(3))), invocation: refinementLimits())
  result.invocation.capture.trace = FetchTraceLimit(49152)
proc reportRun*(fixture: ReportFixture, trace: openArray[byte], cap = reportLimits()):
    RefinementReportResult[RefinedPackage] =
  ## Execute only the captured original package/state; callers cannot substitute per-item outcomes or offsets.
  refinePackage(fixture.state, fixture.package, CoreIndex(5), fixture.parameters, trace,
      fixture.inputs, cap)
