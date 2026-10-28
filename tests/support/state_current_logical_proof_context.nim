# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual current logical producers feed existing bounded generic proof capture; no response supplies its own trusted root.
import std/assertions
import ./state_current_namespace_refresh_context
import ../../src/app/proof_query as app_proof_query
import ../../src/state/current_logical as state_current_logical
import ../../src/state/current_state as state_current_state
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_profile as state_current_profile
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/proof_plan as state_proof_plan
import ../../src/state/proof_view as state_proof_view
import ../../src/state/trie_proof as state_trie_proof
import ../../src/state/proof_global as state_proof_global
import ../../src/state/store as state_store
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_accounts as codec_state_accounts
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
  logical.currentLogicalUpdate.value
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
