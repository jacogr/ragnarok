# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded unchanged-format checkpoint qualification retains one genuine authenticated current update.
## Child prior commitment, computed posterior commitment and explicitly retained finality remain separate facts.
import ./accumulation_current_update as state_accumulation_current_update
import ./checkpoint as state_checkpoint
import ./store as state_store
import ../chain/genesis as chain_genesis
import ../chain/provider as chain_provider
import ../codec/bounded as codec_bounded
import ../codec/state_trie as codec_state_trie
import ../codec/header as codec_header
type
  CurrentCheckpointInfo* = object ## Copied fixed identities do not replace the retained execution certificate or grant independent finality.
    child*, parent*: BlockHash
    slot*: HeaderSlot
    prior*: StateRoot
    posterior*: StateTrieCommitment
    wireBytes*: uint64
  CurrentCheckpointData = ref object # One private immutable source and detached bytes form an acyclic retained graph.
    source: PreparedCurrentChainUpdate
    info: CurrentCheckpointInfo
    wire: seq[byte]
  CurrentUpdateCheckpoint* = object ## Private capture cannot accept a replacement complete map or mutable byte owner.
    data: nil CurrentCheckpointData
  CurrentCheckpointError* {.pure.} = enum ## Default/source, encoding, copy policy and genuine finality absence remain distinct.
    Uninitialized, None, InvalidUpdate, EncodingFailure, LimitExceeded, NoFinality
  CurrentCheckpointResult*[T] = object ## Only selected complete success grants a payload; only encoding refusal carries its original cause.
    case status: CurrentCheckpointError
    of None:
      completed: T
    of EncodingFailure:
      encodingReason: CheckpointError
    else:
      discard # Default, invalid owner and absence/resource refusals expose no prefix or fabricated identity.
func error*[T](outcome: CurrentCheckpointResult[T]): CurrentCheckpointError =
  ## Inspect the selected immutable reason.
  outcome.status
func value*[T](outcome: CurrentCheckpointResult[T]): T {.inline, requires: outcome.status ==
    CurrentCheckpointError.None.} =
  ## Default/refused observations or exports cannot authorize extraction.
  outcome.completed
func encodingError*[T](outcome: CurrentCheckpointResult[T]): CheckpointError {.inline,
    requires: outcome.status == CurrentCheckpointError.EncodingFailure.} =
  ## Preserve the original existing checkpoint encoder's exact resource/source refusal.
  outcome.encodingReason
proc captureCurrentUpdateCheckpoint*(source: PreparedCurrentChainUpdate,
    limit: ByteLimit): CurrentCheckpointResult[CurrentUpdateCheckpoint] =
  ## Operate only on a stable host-owned graph before enqueue or after collection/join; no new worker lease is created or released.
  if not source.ready:
    return CurrentCheckpointResult[CurrentUpdateCheckpoint](
        status: CurrentCheckpointError.InvalidUpdate)
  let snapshot = source.currentUpdateState
  let encoded = encodeFullCheckpoint(snapshot, limit)
  if encoded.error != CheckpointError.None:
    return CurrentCheckpointResult[CurrentUpdateCheckpoint](
      status: CurrentCheckpointError.EncodingFailure,
      encodingReason: encoded.error) # Whole-envelope preflight prevents an exported prefix.
  let child = source.currentUpdateChild
  let info = CurrentCheckpointInfo(child: child.blockHash, parent: child.parentHash,
    slot: HeaderSlot(child.slot), prior: child.priorStateRoot, posterior: snapshot.commitment,
    wireBytes: uint64(encoded.value.len))
  CurrentCheckpointResult[CurrentUpdateCheckpoint](status: CurrentCheckpointError.None,
    completed: CurrentUpdateCheckpoint(data: CurrentCheckpointData(source: source, info: info,
        wire: encoded.value)))
proc currentCheckpointInfo*(captured: CurrentUpdateCheckpoint): CurrentCheckpointResult[
    CurrentCheckpointInfo] =
  ## Return copied fixed observations from an initialized retained certificate.
  let data = captured.data
  if data == nil:
    return CurrentCheckpointResult[CurrentCheckpointInfo](
        status: CurrentCheckpointError.Uninitialized)
  CurrentCheckpointResult[CurrentCheckpointInfo](status: CurrentCheckpointError.None,
      completed: data.info)
proc currentCheckpointSource*(captured: CurrentUpdateCheckpoint): CurrentCheckpointResult[
    PreparedCurrentChainUpdate] =
  ## Retain the exact authenticated producer owner; equal-root maps cannot replace this provenance.
  let data = captured.data
  if data == nil:
    return CurrentCheckpointResult[PreparedCurrentChainUpdate](
        status: CurrentCheckpointError.Uninitialized)
  CurrentCheckpointResult[PreparedCurrentChainUpdate](status: CurrentCheckpointError.None,
      completed: data.source)
proc copyCurrentCheckpoint*(captured: CurrentUpdateCheckpoint,
    limit: ByteLimit): CurrentCheckpointResult[seq[byte]] =
  ## Preflight a fresh independently owned byte copy; callers cannot mutate retained checkpoint bytes.
  let data = captured.data
  if data == nil:
    return CurrentCheckpointResult[seq[byte]](status: CurrentCheckpointError.Uninitialized)
  if uint64(data.wire.len) > uint64(limit):
    return CurrentCheckpointResult[seq[byte]](status: CurrentCheckpointError.LimitExceeded)
  var output = newSeq[byte](data.wire.len)
  for i in 0..<output.len: output[i] = data.wire[i] # The admitted exact extent bounds every copy.
  CurrentCheckpointResult[seq[byte]](status: CurrentCheckpointError.None, completed: output)
proc currentCheckpointFinalized*(captured: CurrentUpdateCheckpoint): CurrentCheckpointResult[BlockHash] =
  ## Preserve the retained view's explicit finality or genuine absence; C15/C16 completion never finalizes the child.
  let data = captured.data
  if data == nil:
    return CurrentCheckpointResult[BlockHash](status: CurrentCheckpointError.Uninitialized)
  let selected = data.source.currentUpdateView.finalizedBlock
  if selected.error == GenesisError.Unavailable:
    return CurrentCheckpointResult[BlockHash](status: CurrentCheckpointError.NoFinality)
  if selected.error != GenesisError.None:
    return CurrentCheckpointResult[BlockHash](status: CurrentCheckpointError.InvalidUpdate)
  CurrentCheckpointResult[BlockHash](status: CurrentCheckpointError.None,
      completed: selected.value.blockHash)
