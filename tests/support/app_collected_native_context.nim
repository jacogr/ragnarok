# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed current receipts and explicitly supplied known namespaces for host consumer witnesses.
import std/assertions
import std/envvars
import std/syncio
import ./state_current_repeated_logical_context
import ./app_collected_logical_context
import ./state_accumulation_current_candidate_context
import ../../src/app/chain as app_chain
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/candidate as app_candidate
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/header as codec_header
type CollectedNativeFixture* = object ## Test descriptors retain immutable genuine receipt/chain and independent supplied declarations.
  fixture*: CurrentRepeatedLogicalFixture
  chain*: ApplicationChain
  receipt*: PreparationCompletion
  declarations*: seq[StateService]
proc nativeBase*(): OwnedReport {.raises.} =
  ## Read only the independently pinned native report fixture selected by the supported runner.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  decodeOwnedReport(bytes, 2).value
proc successorDeclarations*(update: PreparedCurrentChainUpdate,
    original: openArray[StateService]): seq[StateService] =
  ## Retain only supplied raw namespaces; actual known metadata bytes are decoded under the exact current width.
  result = @[]
  for service in original:
    var row = service
    let key = chapterServiceKey(StateChapter(255), row.service)
    let raw = update.currentUpdateState.lookup(key).value.bytes
    let decoded = decodeServiceMetadata(raw, ByteLimit(105))
    assert decoded.error == ServiceMetadataError.None
    assert decoded.value.consumed == raw.len
    row.metadata = decoded.value.metadata
    result.add(row)
proc collectNative*(chain: var ApplicationChain, wire: openArray[byte],
    ancestors: openArray[OwnedHeader], policies: CurrentCandidateLimits): PreparationCompletion {.raises.} =
  ## All aliases remain untouched during the actual fixed-address worker lease and retire only after collection/join.
  var input = default(CurrentBlockInput)
  var worker = default(PreparationWorker)
  let id = receiveCurrent(input, chain, wire, ancestors, policies)
  assert worker.start()
  defer: worker.close()
  let ticket = worker.submit(input, id, chain).value
  worker.waitPreparationDone()
  worker.collect(ticket)
proc collectedNativeFixture*(): CollectedNativeFixture {.raises.} =
  ## Actual native execution supplies every opaque receipt; no completed private result is synthesized.
  let fixture = repeatedLogicalFixture(nativeBase())
  var chain = initApplicationChain(fixture.first.update.currentUpdatePriorView).value
  let owner = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let receipt = collectNative(chain, currentWire(owner), fixture.first.source.older,
      currentCandidateLimits())
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  CollectedNativeFixture(fixture: fixture, chain: chain, receipt: receipt,
    declarations: successorDeclarations(receipt.currentValue.value, fixture.first.services))
