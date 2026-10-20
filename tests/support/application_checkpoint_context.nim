# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A fixed checked-in chainspec supplies explicit structural checkpoint contexts without fabricating execution certificates.

import std/[assertions, envvars, syncio]
import ../../src/app/chain
import ../../src/chain/[genesis, provider, parameters]
import ../../src/codec/[header, bounded, state_layout, state_trie]
import ../../src/state/store

type CheckpointFixtureVariant* {.pure.} = enum ## Each independent mismatch changes exactly one persistence-relevant fact.
  Original, Header, Profile, State
proc checkpointFixture*(variant = CheckpointFixtureVariant.Original): ApplicationChain {.raises.} =
  ## Read only the harness-supplied hash-checked source and retain complete original entries.
  let path = getEnv("RAGNAROK_APPLICATION_CHECKPOINT")
  assert path.len > 0
  let original = initApplicationChain(readFile(path), genesisStoreLimits()).value
  if variant == CheckpointFixtureVariant.Original: return original # Normal callers get the exact selected canonical pair.
  let head = original.chainView.bestBlock.value
  var wire = newSeq[byte](head.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(head.header, wire).error == HeaderError.None
  var configuration = head.chainParameters
  var state = head.stateSnapshot
  if variant == CheckpointFixtureVariant.Header:
    wire[wire.high] = wire[wire.high] xor 1 # Structural capture deliberately makes no seal-authentication claim.
  elif variant == CheckpointFixtureVariant.Profile:
    var encodedParameters = configuration.encodeParameters
    encodedParameters[8] = encodedParameters[8] xor 1 # A deposit-byte change preserves population/time invariants and the exact original header/map.
    configuration = decodeParameters(encodedParameters).value
  else:
    var limits = genesisStoreLimits()
    limits.writes = ElementLimit(1)
    limits.writeValueBytes = ByteLimit(1)
    var entries: seq[StateEntry] = @[]
    for index in 0..<state.commitment.entries:
      let key = state.keyAt(StateEntryIndex(index)).value
      entries.add(StateEntry(key: key, value: state.lookup(
          key).value.bytes)) # Independent test reconstruction preserves the original full mapping.
    var writable = newStateStore(entries, limits).value
    state = writable.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
        value: @[1'u8])]).value # An opaque extra chapter changes only the complete posterior map.
  let captured = captureBlockSnapshot(wire, state, configuration)
  assert captured.error == GenesisError.None
  initApplicationChain(genesisView(captured)).value
