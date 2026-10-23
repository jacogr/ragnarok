# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed current receipts and explicitly supplied known namespaces for host consumer witnesses.
import std/[assertions, envvars, syncio]
import ./[current_repeated_logical_context, collected_logical_context, accumulation_current_candidate_context]
import ../../src/app/[chain, preparation_worker, current_block_input, candidate]
import ../../src/state/[accumulation_current_update, accumulation_round, accumulation_queue,
    report_admission, block_transition, block_admission, store]
import ../../src/codec/[bounded, report_owned, state_composition, state_layout, state_accounts, header]
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
