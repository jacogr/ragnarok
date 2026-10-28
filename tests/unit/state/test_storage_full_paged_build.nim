# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full artifact construction must match an independent byte/tree oracle and reject changed physical replay.
# @@Verification={"arc":"storage_full_paged_build_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../support/state_full_paged_reference
import ../../../src/storage/full_paged_codec as storage_full_paged_codec
import ../../../src/storage/full_paged_stream as storage_full_paged_stream
import ../../../src/storage/full_paged_build as storage_full_paged_build
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/paged_stream as storage_paged_stream
import ../../../src/storage/node_records as storage_node_records
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout

type Producer = ref object ## Caller-owned transport fixture deliberately injects replay and end/failure changes.
  records: seq[TrieRecord]
  mode: int
proc producer(source: Producer): FullPagedProducer =
  ## Two-pass callbacks borrow one caller-owned fixture without cycles or retained production callbacks.
  proc next(pass: int, ordinal: uint64, output: var TrieRecord): FullPagedProducerStep {.closure.} =
    ## Explicit mode controls are independent from the builder's input validation and fingerprint logic.
    if source.mode == 1 and pass == 1 and ordinal == 0: return FullPagedProducerStep.Failed
    if ordinal >= uint64(source.records.len):
      if source.mode == 2: return FullPagedProducerStep.Item
      return FullPagedProducerStep.End
    if source.mode == 3 and pass == 1: return FullPagedProducerStep.End
    output = source.records[int(ordinal)]
    if source.mode == 4 and pass == 1 and output.kind == TrieRecordKind.Branch:
      # JAM B masks this bit, so the altered branch still passes local record hashing.
      var left = array[32, byte](output.left)
      left[0] = left[0] xor 128
      output.left = StateNodeHash(left)
    FullPagedProducerStep.Item
  next
proc output(io: FullPagedTestIO): PagedOutput =
  ## Test-only resident output exposes complete writes and actual refused append boundaries.
  proc append(bytes: openArray[byte]): bool {.closure.} =
    ## A failed append may preserve a forensic prefix; no successful builder receipt follows.
    inc io.calls
    if io.calls == io.failAt:
      for index in 0..<bytes.len div 2: io.bytes.add(bytes[index]) # Deliberate short failed write.
      return false
    for octet in bytes: io.bytes.add(octet) # Exact test append.
    true
  PagedOutput(source: io.input, append: append)
func limits(): FullPagedBuildLimits =
  ## Construction and complete admission have distinct finite work policies.
  FullPagedBuildLimits(admission: policy(), producerCalls: ElementLimit(10000),
    ioCalls: ElementLimit(10000), hashes: ElementLimit(10000), readBytes: ByteLimit(1000000),
    writeBytes: ByteLimit(1000000))
proc build(fixture: FullPagedFixture, source: Producer,
    selectedLimits: FullPagedBuildLimits): FullPagedBuildResult =
  ## Fresh output/scratch ensure each attempt has independent forensic and visited bytes.
  buildFullPaged(FullPagedTestIO().output, FullPagedTestIO(bytes: newSeq[byte](
      fixture.records.len*2)).scratch,
    source.producer, fixture.header, selectedLimits)
let left = leaf(0, @[1'u8, 2, 3])
let right = leaf(128, newSeq[byte](4097))
let parent = branch(left, right)
let ordinary = fixture(@[left, right, parent], parent, @[claim(parent, 2, 3, 4100)])

block independentBytes:
  # Positive controls compare every constructed byte to an independently scheduled complete digest tree.
  for cache in 0..1:
    var budget = limits()
    budget.admission.cachePages = ElementLimit(cache)
    let bytes = FullPagedTestIO()
    let built = buildFullPaged(bytes.output, FullPagedTestIO(bytes: newSeq[byte](6)).scratch,
      Producer(records: ordinary.records).producer, ordinary.header, budget)
    assert built.error == FullPagedBuildError.None
    assert bytes.bytes == ordinary.io.bytes
    assert built.value.checked.initialized
    assert built.value.producerCalls == 8
    assert built.value.writeBytes == ordinary.header.geometry.byteLength

block replayAndCounts:
  # Failed, early/late end and valid same-root physical replay mutations all refuse successful construction.
  for mode in 1..4:
    let built = ordinary.build(Producer(records: ordinary.records, mode: mode), limits())
    assert built.error == (if mode == 4: FullPagedBuildError.ChangedInput else:
      FullPagedBuildError.ProducerFailure)
  var missing = ordinary.records
  missing.setLen(2)
  assert ordinary.build(Producer(records: missing), limits()).error != FullPagedBuildError.None

block work:
  # Exact observed authoring quotas succeed independently of the final admission's own quotas.
  let observed = ordinary.build(Producer(records: ordinary.records), limits()).value
  var exact = limits()
  exact.producerCalls = ElementLimit(observed.producerCalls)
  exact.ioCalls = ElementLimit(observed.ioCalls)
  exact.hashes = ElementLimit(observed.hashes)
  exact.readBytes = ByteLimit(observed.readBytes)
  exact.writeBytes = ByteLimit(observed.writeBytes)
  assert ordinary.build(Producer(records: ordinary.records), exact).error ==
      FullPagedBuildError.None
  for channel in 0..4:
    # Each individually one-short policy must preserve only a refused forensic prefix.
    var short = exact
    case channel
    of 0: short.producerCalls = ElementLimit(observed.producerCalls-1)
    of 1: short.ioCalls = ElementLimit(observed.ioCalls-1)
    of 2: short.hashes = ElementLimit(observed.hashes-1)
    of 3: short.readBytes = ByteLimit(observed.readBytes-1)
    else: short.writeBytes = ByteLimit(observed.writeBytes-1)
    assert ordinary.build(Producer(records: ordinary.records), short).error ==
        FullPagedBuildError.LimitExceeded

block ioFaults:
  # Inject every output read/extent/append callback failure, including short failed writes during digest emission.
  let control = FullPagedTestIO()
  assert buildFullPaged(control.output, FullPagedTestIO(bytes: newSeq[byte](6)).scratch,
    Producer(records: ordinary.records).producer, ordinary.header, limits()).error ==
        FullPagedBuildError.None
  for index in 1..control.calls:
    let failed = FullPagedTestIO(failAt: index)
    assert buildFullPaged(failed.output, FullPagedTestIO(bytes: newSeq[byte](6)).scratch,
      Producer(records: ordinary.records).producer, ordinary.header, limits()).error !=
          FullPagedBuildError.None

block retirement:
  # Two-pass producer closures, forensic output and disposable scratch leave no retained allocation cycles.
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    assert ordinary.build(Producer(records: ordinary.records), limits()).error ==
        FullPagedBuildError.None
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_full_paged_build", 1000, before, after)
echo "storage full paged build PASS"
