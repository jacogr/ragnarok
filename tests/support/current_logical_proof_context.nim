# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual current logical producers feed existing bounded generic proof capture; no response supplies its own trusted root.
import std/assertions
import ./current_namespace_refresh_context
import ../../src/app/proof_query
import ../../src/state/[current_logical, current_state, current_globals, current_profile,
    accumulation_current_update, proof_plan, proof_view, trie_proof, proof_global, store]
import ../../src/chain/[provider, genesis]
import ../../src/codec/[bounded, state_layout, state_trie, state_composition, state_service_values, state_accounts]
proc logicalProofLimits*(): ProofQueryLimits =
  ## Fixed independent policies cover actual namespace fixtures without deriving budgets or authority from response bytes.
  ProofQueryLimits(map: StateTrieLimits(items: ElementLimit(128), perValue: ByteLimit(65536),
      totalValueBytes: ByteLimit(262144), nodes: TrieNodeLimit(1024)), proof: StateProofLimits(
      nodes: ElementLimit(249), valueBytes: ByteLimit(65536)), aggregate: StateProofBatchLimits(
      items: ElementLimit(32), nodes: ElementLimit(7968), valueBytes: ByteLimit(262144)),
      view: ProofViewLimits(items: ElementLimit(32), valueBytes: ByteLimit(262144)),
      wireBytes: ByteLimit(1048576), hashes: ProofHashLimit(10000000))
proc logicalProducer*(logical: CurrentLogicalState): PreparedCurrentChainUpdate =
  ## Follow only guarded original source provenance; callers must hold the canonical host gate open.
  logical.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value
proc logicalProofPlan*(): StateProofPlan =
  ## All sixteen global keys plus one retained storage value and an independently selected proven-absent fixed key.
  var keys: seq[StateKey] = @[]
  for i in 1..16: keys.add(chapterKey(StateChapter(uint8(i))))
  keys.add(serviceStorageKey(ServiceIndex(99), @[5'u8], ByteLimit(1)).value)
  keys.add(chapterServiceKey(StateChapter(255), ServiceIndex(123456)))
  captureStateProofPlan(keys, ElementLimit(18)).value
proc logicalProofQuery*(logical: CurrentLogicalState, plan: StateProofPlan): ProofQuery =
  ## Temporary selected/update aliases retire before a caller can enqueue the sole returned query.
  let selected = logical.logicalProducer.currentUpdateView.bestBlock
  captureProofQuery(selected, plan, logicalProofLimits()).value
proc checkLogicalProof*(logical: CurrentLogicalState, view: ProofView, slot: uint32) =
  ## Existing typed chapter codecs consume authenticated evidence under this producer's original profile; no full-map certificate is created.
  let producer = logical.logicalProducer
  let profile = logical.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedStateProfile.value
  let policy = namespaceLogicalLimits().globals.chapter
  assert uint32(view.readGlobalTime.value) == slot
  for i in 1..16:
    let chapter = StateChapterId(i)
    assert view.readProofChapter(chapter, profile, policy).error == GlobalProofError.None
    let key = chapterKey(StateChapter(uint8(i)))
    assert view.lookup(key).value.bytes == producer.currentUpdateState.lookup(key).value.bytes
  assert not view.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(123456))).value.present
  assert view.len == 18 # Canonical plan order places sixteen chapter keys before service99 storage and service123456 metadata.
  let storage = view.lookupAt(16).value
  let actual = producer.currentUpdateState.lookup(storage.key).value
  assert storage.present and storage.bytes.len == 0 and storage.bytes == actual.bytes
