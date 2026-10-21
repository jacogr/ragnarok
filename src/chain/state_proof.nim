# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind proof generation and verification to one selected immutable block's posterior complete state.
## Header prior-state roots and transport-supplied identities never substitute for this explicit selection.
import ./genesis
import ../state/[trie_proof, snapshot_proof]
import ../codec/[state_layout, state_trie]
proc generateBlockStateProof*(selected: BlockSnapshotResult, query: StateKey,
    mapLimits: StateTrieLimits, limits: StateProofLimits): StateProofResult[StateProof] =
  ## A guarded block result retains its exact complete map; default/refused selection has no empty fallback.
  if selected.error != GenesisError.None:
    return proofFailure[StateProof](StateProofError.Uninitialized)
  generateStateProof(selected.value.stateSnapshot, query, mapLimits, limits)
proc verifyBlockStateProof*(selected: BlockSnapshotResult, proof: StateProof, query: StateKey,
    limits: StateProofLimits): StateProofResult[VerifiedStateLookup] =
  ## Use the selected block's posterior map commitment, which differs from its header's parent-state root.
  if selected.error != GenesisError.None:
    return proofFailure[VerifiedStateLookup](StateProofError.Uninitialized)
  verifyStateProof(proof, selected.value.stateRoot, query, limits)
