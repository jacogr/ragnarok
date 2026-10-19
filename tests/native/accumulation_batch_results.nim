# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed common-source batches expose no partial account/provision state or wrong-alternative reasons.

import std/cmdline
import ../../src/state/[accumulation_batch, accumulation_provisions, store]
import ../../src/codec/[header, state_layout]
import ../support/accumulation_batch_context

let argument = paramStr(1)
let writes = (if argument == "account": 1'u64 elif argument == "provision": 2'u64 else: 64'u64)
let fixture = batchFixture(writes = writes)
let first = batchExecution(fixture, 0)
let second = batchExecution(fixture, 1)
let prior = fixture.state.snapshot.value
var result = prepareAccumulationBatch(fixture.inputs, prior, [first, second], HeaderSlot(128),
    batchPolicy())
case argument
of "default":
  result = default(AccumulationBatchResult[PreparedAccumulationBatch])
  discard result.value
of "duplicate":
  result = prepareAccumulationBatch(fixture.inputs, prior, [first, first], HeaderSlot(128),
      batchPolicy())
  discard result.value
of "source":
  result = prepareAccumulationBatch(batchInputSet(), prior, [first, second], HeaderSlot(128),
      batchPolicy())
  discard result.value
of "index":
  let index = if argument == "index": high(uint64) else: 0'u64
  discard result.value.batchOutcomeAt(AccumulationProvisionSourceIndex(index)).value
of "wrong-store":
  discard result.storeError
of "wrong-terminal":
  discard result.terminalError
of "wrong-normalization", "wrong-provision":
  result = prepareAccumulationBatch(fixture.inputs, prior, [first, second], HeaderSlot(7),
      batchPolicy())
  if argument == "wrong-normalization":
    discard result.normalizationError # Actual TerminalFailure with the wrong nested reason.
  else:
    discard result.provisionError
else:
  var plan = result.value
  var state = fixture.state
  if argument == "apply-default":
    plan = default(PreparedAccumulationBatch) # Dynamic selection retains a runtime ownership probe.
  if argument == "stale":
    discard state.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
        value: @[1'u8])]).value
  discard applyAccumulationBatch(state, plan).value
