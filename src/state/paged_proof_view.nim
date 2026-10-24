# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded paged light evidence becomes an ordinary immutable ProofView only after state-layer recapture and verification.
## Unknown stored queries remain missing witnesses; no partial evidence becomes a complete StateStore.
import std/algorithm
import ./[trie_proof, proof_view]
import ../storage/[paged_store, paged_stream, paged_codec]
import ../codec/[bounded, state_layout, state_trie]

type
  PagedProofViewLimits* = object ## Native per-query work and per-proof/batch/view retention ceilings remain independent.
    proof*: StateProofLimits
    batch*: StateProofBatchLimits
    view*: ProofViewLimits
    work*: PagedWorkLimits
  PagedProofViewError* {.pure.} = enum ## Failed/default operations expose no proof-view prefix or fake authenticated absence.
    Uninitialized, None, LimitExceeded, LengthOverflow, WrongRoot, MissingWitness,
    NativeFailure, ProofFailure, ViewFailure
  PagedProofViewResult*[T] = object ## Nominal storage/state proof types cross only through detached canonical transport and verification.
    case status: PagedProofViewError
    of None: completed: T                        # Only a complete requested batch grants partial read authority.
    of NativeFailure: nativeCause: PagedNativeResult[bool] # Keep native uncertainty/corruption distinct.
    of ProofFailure: proofCause: StateProofError # Preserve state verifier refusals.
    of ViewFailure: viewCause: ProofViewError    # Preserve ordinary partial-view policy.
    else: discard                                # Plain refusals and defaults contain no authority.
func error*[T](outcome: PagedProofViewResult[T]): PagedProofViewError =
  ## Inspect the selected extraction, state-verification or view-capture stage.
  outcome.status
func value*[T](outcome: PagedProofViewResult[T]): T {.inline, requires: outcome.status ==
    PagedProofViewError.None.} =
  ## Success alone exposes the complete requested immutable partial evidence view.
  outcome.completed
func nativeFailure*[T](outcome: PagedProofViewResult[T]): PagedNativeResult[bool] {.requires:
    outcome.status == PagedProofViewError.NativeFailure.} =
  ## Retain original file/stream/proof causes instead of reclassifying corruption as unavailable evidence.
  outcome.nativeCause
func proofError*[T](outcome: PagedProofViewResult[T]): StateProofError {.requires:
    outcome.status == PagedProofViewError.ProofFailure.} =
  ## State proof refusal cannot expose a successfully verified prefix.
  outcome.proofCause
func viewError*[T](outcome: PagedProofViewResult[T]): ProofViewError {.requires:
    outcome.status == PagedProofViewError.ViewFailure.} =
  ## Sorted-view policy failures remain separate from native proof integrity.
  outcome.viewCause
func refused[T](reason: PagedProofViewError): PagedProofViewResult[T] =
  ## Plain policy/root/missing-evidence refusals retain no view or native owner.
  PagedProofViewResult[T](status: reason)
func nativeFailed[T, U](outcome: PagedNativeResult[U]): PagedProofViewResult[T] {.requires:
    outcome.error != PagedNativeError.None.} =
  ## Selected native failure conversion never fabricates successful proof authority.
  PagedProofViewResult[T](status: PagedProofViewError.NativeFailure, nativeCause: outcome.failure)
proc compareKey(a, b: StateKey): int =
  ## Duplicate-query preflight sorts fixed identities without touching any proof or value payload.
  let left = array[31, byte](a)
  let right = array[31, byte](b)
  for index in 0..<31:
    # Canonical MSB order compares fixed key bytes, never value or witness payloads.
    if left[index] < right[index]: return -1 # The first unequal octet decides order.
    if left[index] > right[index]: return 1 # Equal prefixes continue to the next octet.
  0
proc readPagedProofView*(reader: var PagedReader, expected: StateRoot,
    queries: openArray[StateKey], limits: PagedProofViewLimits): PagedProofViewResult[ProofView] =
  ## Stage every requested witness privately; immutable state ProofView construction follows complete native extraction and re-verification.
  if uint64(queries.len) > uint64(limits.batch.items) or uint64(queries.len) > uint64(
      limits.view.items):
    # Reject before allocating descriptor scratch or retaining another state witness.
    return refused[ProofView](PagedProofViewError.LimitExceeded)
  if queries.len > high(int) div sizeof(StateProofQuery) or queries.len > high(int) div sizeof(StateKey):
    # Host allocation extents must be representable independently of logical policy ceilings.
    return refused[ProofView](PagedProofViewError.LengthOverflow)
  let selected = reader.selected
  if selected.error != PagedNativeError.None:
    # Default, closed or poisoned owners cannot grant root authority.
    return nativeFailed[ProofView, PagedManifest](selected)
  if array[32, byte](selected.value.root) != array[32, byte](expected):
    # CURRENT selection never replaces the caller's independently supplied expected root.
    return refused[ProofView](PagedProofViewError.WrongRoot)
  var sorted = newSeq[StateKey](queries.len)
  for index in 0..<queries.len: sorted[index] = queries[index] # Private fixed-size identity scratch only.
  sorted.sort(compareKey)
  for index in 1..<sorted.len:
    # Reject ambiguous duplicates before any native source lookup or proof copying.
    if array[31, byte](sorted[index-1]) == array[31, byte](sorted[index]):
      return PagedProofViewResult[ProofView](status: PagedProofViewError.ProofFailure,
        proofCause: StateProofError.DuplicateKey)
  var staged = newSeq[StateProofQuery](queries.len)
  var nodes, bytes = 0'u64
  for index, query in queries:
    # Native lookup authenticates one bounded proof under the held independent light root before lending transport.
    let captured = reader.readProof(query, limits.work)
    if captured.error == PagedNativeError.UnknownKey:
      # An unavailable stored query is never authenticated absence.
      return refused[ProofView](PagedProofViewError.MissingWitness)
    if captured.error != PagedNativeError.None:
      # Retain the original selected file, stream or storage-proof failure.
      return nativeFailed[ProofView, PagedProofLookup](captured)
    let raw = captured.value.proof
    if array[31, byte](raw.key) != array[31, byte](query):
      # Detached transport must still identify this exact request.
      return PagedProofViewResult[ProofView](status: PagedProofViewError.ProofFailure,
        proofCause: StateProofError.KeyMismatch)
    let count = uint64(raw.proof.nodes.len)
    let size = uint64(raw.proof.value.len)
    if count > uint64(limits.proof.nodes) or size > uint64(limits.proof.valueBytes) or
        count > uint64(limits.batch.nodes)-nodes or size > uint64(limits.batch.valueBytes)-bytes or
        size > uint64(limits.view.valueBytes)-bytes:
      # Previously admitted sums stay below every ceiling, making each subtraction/addition safe.
      return refused[ProofView](PagedProofViewError.LimitExceeded)
    let witness = captureStateProof(raw.proof.nodes, raw.proof.value, limits.proof)
    if witness.error != StateProofError.None:
      # State proof capture is independent from storage verification and grants no lookup authority.
      return PagedProofViewResult[ProofView](status: PagedProofViewError.ProofFailure,
          proofCause: witness.error)
    staged[index] = StateProofQuery(key: query, proof: witness.value)
    nodes += count
    bytes += size
  let verified = verifyStateProofs(staged, expected, limits.proof, limits.batch)
  if verified.error != StateProofError.None:
    # No earlier verified prefix escapes a later state-layer verification failure.
    return PagedProofViewResult[ProofView](status: PagedProofViewError.ProofFailure,
        proofCause: verified.error)
  let view = captureProofView(verified.value, expected, limits.view)
  if view.error != ProofViewError.None:
    # Ordinary ProofView construction remains the final immutable partial-state boundary.
    return PagedProofViewResult[ProofView](status: PagedProofViewError.ViewFailure,
        viewCause: view.error)
  PagedProofViewResult[ProofView](status: PagedProofViewError.None, completed: view.value)
