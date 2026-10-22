# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate all global chapter serializations from one complete immutable map without hashing.
## Retained source identity and typed chapters confer no valid-state or trusted-root authority.
import ../codec/[bounded, state_layout, state_composition]
import ./store

type
  GlobalStateLimits* = object ## Per-chapter codec work and aggregate detached chapter bytes are independent policies.
    chapter*: StateChapterPolicy
    totalBytes*: ByteLimit
  GlobalStateError* {.pure.} = enum ## Failure exposes neither a prefix of chapters nor a replacement state.
    Uninitialized, None, InvalidSource, MissingChapter, LimitExceeded, ChapterFailure
  GlobalStateData = ref object # One acyclic owner retains the genuine complete source and immutable typed chapter owners.
    source: StateStoreSnapshot
    chapters: StateChapters
    bytes: uint64
  ValidatedGlobalState* = object ## Only complete validation constructs this serialization certificate.
    data: nil GlobalStateData
  GlobalStateResult*[T] = object    ## Private tags and payloads preserve default/failure extraction guards.
    case status: GlobalStateError
    of None:
      completed: T                  # No partial typed chapter array escapes on failure.
    of MissingChapter:
      missing: StateChapterId       # Complete source absence is different from missing partial evidence.
    of ChapterFailure:
      chapter: StateChapterId
      reason: StateCompositionError # Preserve the exact existing codec/configuration refusal.
    else:
      discard

func error*[T](outcome: GlobalStateResult[T]): GlobalStateError =
  ## Inspect the alternative without authorizing payload mutation.
  outcome.status
func value*[T](outcome: GlobalStateResult[T]): T {.inline,
    requires: outcome.status == GlobalStateError.None.} =
  ## Only complete success grants a retained source or chapter owner.
  outcome.completed
func failedChapter*[T](outcome: GlobalStateResult[T]): StateChapterId {.inline,
    requires: outcome.status in {GlobalStateError.MissingChapter,
        GlobalStateError.ChapterFailure}.} =
  ## Identify the exact failed global component only for a chapter-specific refusal.
  if outcome.status == GlobalStateError.MissingChapter:
    outcome.missing # Absence in a complete map is established by the source lookup.
  else:
    outcome.chapter # A present value was refused by the existing exact decoder.
func chapterError*[T](outcome: GlobalStateResult[T]): StateCompositionError {.inline,
    requires: outcome.status == GlobalStateError.ChapterFailure.} =
  ## Inspect the nested decoder reason only for an actual present chapter refusal.
  outcome.reason

proc validateGlobalState*(source: StateStoreSnapshot, profile: StateProfile,
    limits: GlobalStateLimits): GlobalStateResult[ValidatedGlobalState] =
  ## Preflight every complete chapter length before copying or decoding any input value.
  if not sameStateSnapshot(source, source):
    return GlobalStateResult[ValidatedGlobalState](
        status: GlobalStateError.InvalidSource) # A default owner cannot supply a complete map.
  var total = 0'u64
  for ordinal in 1..16:
    let chapter = StateChapterId(ordinal) # Fixed validated chapter domain avoids unsupported enum-range iteration.
    let found = source.lookup(chapterKey(StateChapter(uint8(ord(chapter)))))
    if found.error == StateStoreError.MissingKey:
      return GlobalStateResult[ValidatedGlobalState](status: GlobalStateError.MissingChapter,
        missing: chapter) # Never synthesize an absent required chapter.
    let size = uint64(found.value.byteLength)
    if size > uint64(limits.chapter.maxBytes) or size > uint64(limits.totalBytes)-total:
      return GlobalStateResult[ValidatedGlobalState](
          status: GlobalStateError.LimitExceeded) # Subtraction proves aggregate addition before any detached copy.
    total += size
  var chapters = default(StateChapters)
  for ordinal in 1..16:
    let chapter = StateChapterId(ordinal) # Fixed validated chapter domain avoids unsupported enum-range iteration.
    let found = source.lookup(chapterKey(StateChapter(uint8(ord(chapter))))).value
    let captured = captureStateChapter(chapter, found.bytes, profile, limits.chapter)
    if captured.error != StateCompositionError.None:
      return GlobalStateResult[ValidatedGlobalState](status: GlobalStateError.ChapterFailure,
        chapter: chapter, reason: captured.error) # Earlier temporary chapters retire without publishing a prefix.
    chapters[chapter] = captured.value
  GlobalStateResult[ValidatedGlobalState](status: GlobalStateError.None,
    completed: ValidatedGlobalState(data: GlobalStateData(source: source, chapters: chapters,
      bytes: total)))

proc globalSource*(state: ValidatedGlobalState): GlobalStateResult[StateStoreSnapshot] =
  ## Return the exact original complete-map owner, preserving all opaque service entries unchanged.
  if state.data == nil:
    return GlobalStateResult[StateStoreSnapshot](status: GlobalStateError.Uninitialized) # Default certificates retain no source.
  GlobalStateResult[StateStoreSnapshot](status: GlobalStateError.None, completed: state.data.source)
proc globalChapters*(state: ValidatedGlobalState): GlobalStateResult[StateChapters] =
  ## Copy the fixed chapter handle array; replacing caller slots cannot edit the retained certificate.
  if state.data == nil:
    return GlobalStateResult[StateChapters](status: GlobalStateError.Uninitialized) # No default chapter array pretends to be validated.
  GlobalStateResult[StateChapters](status: GlobalStateError.None, completed: state.data.chapters)
proc globalByteLength*(state: ValidatedGlobalState): GlobalStateResult[uint64] =
  ## Report validated global bytes only, excluding opaque service values from the codec claim.
  if state.data == nil:
    return GlobalStateResult[uint64](status: GlobalStateError.Uninitialized) # No initialized observation exists.
  GlobalStateResult[uint64](status: GlobalStateError.None, completed: state.data.bytes)
