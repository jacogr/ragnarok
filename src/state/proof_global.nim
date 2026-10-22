# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded global chapter selectors and authenticated reads of partial evidence.
## Typed chapter captures retain existing codec/profile rules without granting complete-map authority.
import std/assertions
import ../codec/[bounded, state_layout, state_safrole, state_composition, state_history, state_authorization]
import ./[proof_plan, proof_view, trie_proof]

type
  GlobalProofError* {.pure.} = enum ## Missing evidence, proven absence and malformed present values remain distinct.
    Uninitialized, None, MissingWitness, AbsentValue, LimitExceeded, InvalidValue, InvalidConfig, InvalidInput
  GlobalProofResult*[T] = object ## Failed/default reads contain a reason and no decoded owner or progress.
    case status: GlobalProofError
    of None: completed: T
    else: discard # Only fully validated values authorize extraction.

func error*[T](outcome: GlobalProofResult[T]): GlobalProofError =
  ## Inspect a read refusal without selecting its guarded payload.
  outcome.status
func value*[T](outcome: GlobalProofResult[T]): T {.inline,
    requires: outcome.status == GlobalProofError.None.} =
  ## Return only a complete fixed value or immutable typed capture.
  outcome.completed

proc planProofChapters*(chapters: openArray[StateChapterId], limit: ElementLimit):
    GlobalProofResult[StateProofPlan] =
  ## Preflight count/native allocation and nominal identities before capturing canonical fixed keys.
  if uint64(chapters.len) > uint64(limit) or chapters.len > high(int) div sizeof(StateKey):
    return GlobalProofResult[StateProofPlan](status: GlobalProofError.LimitExceeded)
  for chapter in chapters:
    # Forged enums must never narrow into an unrelated state namespace.
    if ord(chapter) < 1 or ord(chapter) > 16:
      return GlobalProofResult[StateProofPlan](status: GlobalProofError.InvalidInput)
  var keys = newSeq[StateKey](chapters.len)
  for i, chapter in chapters:
    keys[i] = chapterKey(StateChapter(uint8(ord(chapter)))) # Every ordinal was validated before allocation.
  let captured = captureStateProofPlan(keys, limit)
  if captured.error != ProofPlanError.None:
    # Duplicate selectors are malformed; retain an allocation-policy refusal separately.
    return GlobalProofResult[StateProofPlan](status: (if captured.error ==
        ProofPlanError.LimitExceeded:
      GlobalProofError.LimitExceeded else: GlobalProofError.InvalidInput))
  GlobalProofResult[StateProofPlan](status: GlobalProofError.None, completed: captured.value)
proc planProofChapter*(chapter: StateChapterId, limit: ElementLimit):
    GlobalProofResult[StateProofPlan] =
  ## Request exactly one typed top-level chapter, without root or evidence authority.
  planProofChapters([chapter], limit)

proc chapterBytes(view: ProofView, chapter: StateChapterId,
    limit: ByteLimit): GlobalProofResult[seq[byte]] =
  ## Refuse unavailable evidence and bound cached authenticated length before detaching value bytes.
  if ord(chapter) < 1 or ord(chapter) > 16:
    return GlobalProofResult[seq[byte]](status: GlobalProofError.InvalidConfig)
  let found = view.lookup(chapterKey(StateChapter(uint8(ord(chapter)))))
  if found.error != ProofViewError.None:
    # A valid view lacking this witness cannot establish absence.
    return GlobalProofResult[seq[byte]](status: (if found.error == ProofViewError.Uninitialized:
      GlobalProofError.Uninitialized else: GlobalProofError.MissingWitness))
  let lookup = found.value
  if not lookup.present:
    return GlobalProofResult[seq[byte]](status: GlobalProofError.AbsentValue)
  if uint64(lookup.byteLength) > uint64(limit):
    return GlobalProofResult[seq[byte]](status: GlobalProofError.LimitExceeded)
  GlobalProofResult[seq[byte]](status: GlobalProofError.None, completed: lookup.bytes)

proc readProofChapter*(view: ProofView, chapter: StateChapterId, profile: StateProfile,
    policy: StateChapterPolicy): GlobalProofResult[StateChapterSnapshot] =
  ## Capture one exact typed chapter through the established codec; partial evidence stays partial.
  let bytes = chapterBytes(view, chapter, policy.maxBytes)
  if bytes.error != GlobalProofError.None:
    return GlobalProofResult[StateChapterSnapshot](status: bytes.error)
  let captured = captureStateChapter(chapter, bytes.value, profile, policy)
  if captured.error != StateCompositionError.None:
    # Preserve caller policy/configuration refusals; all remaining codec errors invalidate the value.
    let reason = case captured.error
      of StateCompositionError.InvalidConfig: GlobalProofError.InvalidConfig
      of StateCompositionError.LimitExceeded, StateCompositionError.LengthOverflow:
        GlobalProofError.LimitExceeded
      else: GlobalProofError.InvalidValue
    return GlobalProofResult[StateChapterSnapshot](status: reason)
  GlobalProofResult[StateChapterSnapshot](status: GlobalProofError.None, completed: captured.value)

proc readGlobalTime*(view: ProofView): GlobalProofResult[StateTime] =
  ## Require the exact E4 chapter value; preserve the existing public time reader unchanged.
  let found = view.readProofTime
  if found.error != ProofViewError.None:
    # Every possible readProofTime refusal has a stable global-read classification.
    let reason = case found.error
      of ProofViewError.Uninitialized: GlobalProofError.Uninitialized
      of ProofViewError.MissingWitness: GlobalProofError.MissingWitness
      of ProofViewError.AbsentValue: GlobalProofError.AbsentValue
      else: GlobalProofError.InvalidValue
    return GlobalProofResult[StateTime](status: reason)
  GlobalProofResult[StateTime](status: GlobalProofError.None, completed: found.value)

proc readGlobalEntropy*(view: ProofView, limit: ByteLimit): GlobalProofResult[StateEntropy] =
  ## Extract all four ordered fixed words, bounding authenticated bytes before detaching them.
  let bytes = chapterBytes(view, StateChapterId.Entropy, limit)
  if bytes.error != GlobalProofError.None:
    return GlobalProofResult[StateEntropy](status: bytes.error)
  let decoded = decodeStateEntropy(bytes.value)
  if decoded.error != StateComponentError.None:
    return GlobalProofResult[StateEntropy](status: GlobalProofError.InvalidValue)
  if decoded.value.consumed != bytes.value.len:
    return GlobalProofResult[StateEntropy](status: GlobalProofError.InvalidValue)
  GlobalProofResult[StateEntropy](status: GlobalProofError.None, completed: decoded.value.value)

proc readGlobalHistory*(view: ProofView, config: HistoryConfig): GlobalProofResult[
    HistorySnapshot] =
  ## Decode exact recent history and belt peaks with independent caller cardinality/byte policies.
  let bytes = chapterBytes(view, StateChapterId.History, config.maxBytes)
  if bytes.error != GlobalProofError.None:
    return GlobalProofResult[HistorySnapshot](status: bytes.error)
  let decoded = decodeHistoryState(bytes.value, config)
  if decoded.error != HistoryError.None:
    # Malformed protocol values do not become empty histories or partially decoded owners.
    let reason = case decoded.error
      of HistoryError.InvalidConfig: GlobalProofError.InvalidConfig
      of HistoryError.LimitExceeded, HistoryError.LengthOverflow: GlobalProofError.LimitExceeded
      else: GlobalProofError.InvalidValue
    return GlobalProofResult[HistorySnapshot](status: reason)
  if decoded.value.consumed != bytes.value.len:
    return GlobalProofResult[HistorySnapshot](status: GlobalProofError.InvalidValue)
  GlobalProofResult[HistorySnapshot](status: GlobalProofError.None,
      completed: decoded.value.snapshot)

proc readGlobalAuthorization*(view: ProofView, kind: AuthorizationKind,
    config: AuthorizationConfig): GlobalProofResult[AuthorizationSnapshot] =
  ## Bind the caller's semantic pool/queue choice to its distinct chapter before bounded decoding.
  if ord(kind) < ord(AuthorizationKind.Pools) or ord(kind) > ord(AuthorizationKind.Queues):
    return GlobalProofResult[AuthorizationSnapshot](status: GlobalProofError.InvalidConfig)
  let chapter = if kind == AuthorizationKind.Pools: StateChapterId.Pools else: StateChapterId.Queues
  let bytes = chapterBytes(view, chapter, config.maxBytes)
  if bytes.error != GlobalProofError.None:
    return GlobalProofResult[AuthorizationSnapshot](status: bytes.error)
  let decoded = decodeAuthorization(kind, bytes.value, config)
  if decoded.error != AuthorizationError.None:
    # Pool and fixed-queue cardinalities remain the codec's separate protocol contracts.
    let reason = case decoded.error
      of AuthorizationError.InvalidConfig: GlobalProofError.InvalidConfig
      of AuthorizationError.LimitExceeded, AuthorizationError.LengthOverflow: GlobalProofError.LimitExceeded
      else: GlobalProofError.InvalidValue
    return GlobalProofResult[AuthorizationSnapshot](status: reason)
  if decoded.value.consumed != bytes.value.len:
    return GlobalProofResult[AuthorizationSnapshot](status: GlobalProofError.InvalidValue)
  GlobalProofResult[AuthorizationSnapshot](status: GlobalProofError.None,
      completed: decoded.value.snapshot)

proc readGlobalValidators*(view: ProofView, chapter: ValidatorChapter,
    config: ValidatorStateConfig): GlobalProofResult[ValidatorStateSnapshot] =
  ## Select one exact roster identity; neither another roster's witness nor an absent roster is a fallback.
  if ord(chapter) < ord(ValidatorChapter.Staging) or ord(chapter) > ord(ValidatorChapter.Previous):
    return GlobalProofResult[ValidatorStateSnapshot](status: GlobalProofError.InvalidConfig)
  let bytes = chapterBytes(view, StateChapterId(ord(chapter)), config.maxBytes)
  if bytes.error != GlobalProofError.None:
    return GlobalProofResult[ValidatorStateSnapshot](status: bytes.error)
  let decoded = decodeStateValidators(bytes.value, config)
  if decoded.error != StateComponentError.None:
    # Existing population rules and independent resource ceilings remain the codec's authority.
    let reason = case decoded.error
      of StateComponentError.InvalidConfig: GlobalProofError.InvalidConfig
      of StateComponentError.LimitExceeded, StateComponentError.LengthOverflow: GlobalProofError.LimitExceeded
      else: GlobalProofError.InvalidValue
    return GlobalProofResult[ValidatorStateSnapshot](status: reason)
  if decoded.value.consumed != bytes.value.len:
    return GlobalProofResult[ValidatorStateSnapshot](status: GlobalProofError.InvalidValue)
  GlobalProofResult[ValidatorStateSnapshot](status: GlobalProofError.None,
      completed: decoded.value.value)
