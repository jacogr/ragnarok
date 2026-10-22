# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded immutable path witnesses for the pinned state trie. Capture validates structure only;
## independently supplied roots and keys grant lookup authority through a separate verifier.
import ../codec/[bounded, state_layout]

type
  StateProofLimits* = object ## Independent ceilings apply before path/value copying or hashing.
    nodes*: ElementLimit
    valueBytes*: ByteLimit
  StateProofError* {.pure.} = enum ## Failure alternatives never expose a proof prefix or lookup payload.
    Uninitialized, None, LimitExceeded, InvalidProof, InvalidIndex, RootMismatch,
    KeyMismatch, BackendFailure, MissingValue, StoreFailure
  ProofData = ref object ## Private acyclic ownership freezes copied canonical nodes and supplied bytes.
    nodes: seq[EncodedStateNode]
    value: seq[byte]
  StateProof* = object ## An unverified path witness is deliberately distinct from a verified lookup.
    data: nil ProofData
  StateProofResult*[T] = object ## Success alone owns a complete checked result.
    case status: StateProofError
    of None:
      completed: T
    else:
      discard                   # Default and failure retain only their reason.

func error*[T](outcome: StateProofResult[T]): StateProofError =
  ## Inspect a reason without authorizing extraction.
  outcome.status
func value*[T](outcome: StateProofResult[T]): T {.inline,
    requires: outcome.status == StateProofError.None.} =
  ## Require explicit success even in optimized checked builds.
  outcome.completed
func valid*(proof: StateProof): bool =
  ## Structural capture alone never establishes commitment or membership.
  proof.data != nil
func len*(proof: StateProof): int =
  ## Defaults have no captured nodes and cannot become empty-trie evidence.
  let data = proof.data
  if data == nil: 0 else: data.nodes.len
proc nodeAt*(proof: StateProof, index: int): StateProofResult[EncodedStateNode] =
  ## Copy one fixed node, with invalid owner/index refusal instead of silent defaults.
  let data = proof.data
  if data == nil:
    return StateProofResult[EncodedStateNode](status: StateProofError.Uninitialized)
  if index < 0 or index >= data.nodes.len:
    return StateProofResult[EncodedStateNode](status: StateProofError.InvalidIndex)
  StateProofResult[EncodedStateNode](status: StateProofError.None,
    completed: data.nodes[index])
proc suppliedValue*(proof: StateProof): StateProofResult[seq[byte]] =
  ## Return detached unverified bytes; callers must not interpret them as authenticated state.
  let data = proof.data
  if data == nil:
    return StateProofResult[seq[byte]](status: StateProofError.Uninitialized)
  var copied = newSeq[byte](data.value.len)
  for i, octet in data.value:
    copied[i] = octet # No mutable backing storage escapes the immutable owner.
  StateProofResult[seq[byte]](status: StateProofError.None, completed: copied)
proc captureStateProof*(nodes: openArray[EncodedStateNode], supplied: openArray[byte],
    limits: StateProofLimits): StateProofResult[StateProof] =
  ## Bound and validate every canonical node before publishing one immutable witness.
  if nodes.len > 249 or uint64(nodes.len) > uint64(limits.nodes) or
      uint64(supplied.len) > uint64(limits.valueBytes):
    return StateProofResult[StateProof](status: StateProofError.LimitExceeded)
  for i, node in nodes:
    # Each nonterminal is a branch; a terminal leaf ends the path after at most 248 bits.
    let decoded = decodeStateNode(array[64, byte](node))
    if decoded.error != StateLayoutError.None:
      return StateProofResult[StateProof](status: StateProofError.InvalidProof)
    if i < nodes.len - 1 and decoded.value.node.kind != StateNodeKind.Branch:
      return StateProofResult[StateProof](status: StateProofError.InvalidProof)
    if i == nodes.len - 1 and decoded.value.node.kind == StateNodeKind.Branch:
      return StateProofResult[StateProof](status: StateProofError.InvalidProof)
  var copiedNodes = newSeq[EncodedStateNode](nodes.len)
  for i, node in nodes:
    copiedNodes[i] = node # Fixed node copies preserve exact canonical bytes.
  var copiedValue = newSeq[byte](supplied.len)
  for i, octet in supplied:
    copiedValue[i] = octet # Capture never shares mutable caller sequences.
  StateProofResult[StateProof](status: StateProofError.None,
    completed: StateProof(data: ProofData(nodes: copiedNodes, value: copiedValue)))
