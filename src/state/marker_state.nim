# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Read-only GP 0.8.0 header marker validation against retained parent and staged full-state
## snapshots.
##
## Exposes validateSafroleHeaderMarkers over parent/staged full-state snapshots and explicit
## marker policies.

import ../codec/[state_safrole, state_consensus, state_layout, header]
import ./[safrole_markers, store]

## Preserve absent/default/bounded state distinctions; lookup never hashes or mutates the map.
func stateError(reason: StateStoreError): SafroleMarkerError =
  case reason
  of StateStoreError.Uninitialized: SafroleMarkerError.Uninitialized # A default snapshot cannot authorize header validation.
  of StateStoreError.MissingKey: SafroleMarkerError.MissingState # Required state is never synthesized as genesis data.
  of StateStoreError.LimitExceeded: SafroleMarkerError.LimitExceeded # Preserve explicit resource refusal.
  of StateStoreError.LengthOverflow: SafroleMarkerError.LengthOverflow # Preserve checked native extent refusal.
  else: SafroleMarkerError.InvalidState # Other lookup errors cannot describe this fixed read-only key set.

proc validateSafroleHeaderMarkers*(parent, staged: StateStoreSnapshot,
    candidate: OwnedUnsignedHeader, config: SafroleMarkerConfig): SafroleMarkerError =
  ## Bind a structurally decoded unsigned header to parent C(4)/C(6)/C(11) and staged C(4)/C(11).
  ## The header slot must equal staged time; caller authenticates entropy proofs and earlier stages separately.
  ## Both snapshots remain immutable on success and refusal; this performs no writes or commitment hashing.
  let info = unsignedHeaderInfo(candidate)
  if info.error != HeaderError.None:
    return SafroleMarkerError.InvalidHeader # A default header cannot stand for a decoded empty marker pair.
  let oldChapter = parent.lookup(chapterKey(StateChapter(4)))
  if oldChapter.error != StateStoreError.None:
    return stateError(oldChapter.error) # The original contest survives staged admission resets.
  let oldEntropy = parent.lookup(chapterKey(StateChapter(6)))
  if oldEntropy.error != StateStoreError.None:
    return stateError(oldEntropy.error) # Epoch markers bind parent entropy, not the posterior accumulator.
  let oldTime = parent.lookup(chapterKey(StateChapter(11)))
  if oldTime.error != StateStoreError.None:
    return stateError(oldTime.error) # No implicit slot-zero parent.
  let chapter = staged.lookup(chapterKey(StateChapter(4)))
  if chapter.error != StateStoreError.None:
    return stateError(chapter.error) # Pending validator pairs come from completed staged rotation.
  let time = staged.lookup(chapterKey(StateChapter(11)))
  if time.error != StateStoreError.None:
    return stateError(time.error) # Recorded time must match this exact candidate header.
  if oldEntropy.value.byteLength != 128 or oldTime.value.byteLength != 4 or time.value.byteLength != 4:
    return SafroleMarkerError.InvalidState # Bound fixed copies and reject both truncation and suffixes.
  let oversizedParent = uint64(oldChapter.value.byteLength) > uint64(config.state.maxBytes)
  let oversizedStaged = uint64(chapter.value.byteLength) > uint64(config.state.maxBytes)
  if oversizedParent or oversizedStaged:
    return SafroleMarkerError.LimitExceeded # Check both dynamic chapter ceilings before copying either input.
  let entropy = decodeStateEntropy(oldEntropy.value.bytes)
  let previous = decodeStateTime(oldTime.value.bytes)
  let stagedTime = decodeStateTime(time.value.bytes)
  let invalidTime = previous.error != StateComponentError.None or stagedTime.error !=
      StateComponentError.None
  if invalidTime or entropy.error != StateComponentError.None:
    return SafroleMarkerError.InvalidState # Select every fixed-codec success before extracting values.
  let target = StateTime(uint32(info.value.slot))
  if uint32(stagedTime.value.value) != uint32(target):
    return SafroleMarkerError.InvalidState # Refuse missing/out-of-order time staging or a header for another slot.
  let expected = deriveSafroleMarkers(oldChapter.value.bytes, chapter.value.bytes,
    previous.value.value, target, entropy.value.value, config)
  if expected.error != SafroleMarkerError.None:
    return expected.error # Invalid state/config/chronology publishes no derived marker pair.
  let epoch = headerEpoch(candidate)
  let winners = headerWinners(candidate)
  if epoch.error != HeaderError.None or winners.error != HeaderError.None:
    return SafroleMarkerError.InvalidHeader # Only validated owners from this exact header can reach comparison.
  validateSafroleMarkers(expected.value, epoch.value, winners.value)
