# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted roster fixture construction uses structural codecs, not cryptographic key validation.
import std/assertions
import ../../src/codec/[state_safrole, assurances, bounded]
from ../../src/codec/disputes import OffenderKey
from ../../src/codec/header import EpochSlots
export state_safrole, assurances, bounded, OffenderKey, EpochSlots

## Finite explicit chain policy; each input and posterior roster is bounded independently.
proc rotationRosterConfig*(cores = 341): ValidatorStateConfig =
  assert cores >= 2 and cores <= 341
  ValidatorStateConfig(cores: CoreCount(uint64(cores)), validators: ElementLimit(uint64(cores)*3),
      maxBytes: ByteLimit(uint64(cores)*1008+9))

## Distinct nonzero fields expose wrong-key matching and incomplete record nulling.
proc rotationRecords*(count: int, offset: byte): seq[StateValidator] =
  assert count >= 6 and count <= 1023
  result = newSeq[StateValidator](count)
  for i in 0..<count:
    var bs, ed = default(array[32, byte])
    var bls = default(array[144, byte])
    var metadata = default(array[128, byte])
    for j in 0..<32:
      bs[j] = offset # Bandersnatch is deliberately not the membership key.
      ed[j] = byte(i mod 200+1)
    for j in 0..<144: bls[j] = offset # Opaque BLS bytes must be zeroed too.
    for j in 0..<128: metadata[j] = offset # Metadata is part of the same 336-byte record.
    result[i] = StateValidator(bandersnatch: StateBsKey(bs), ed25519: StateEdKey(ed),
        bls: StateBlsKey(bls), metadata: StateValidatorMetadata(metadata))

## Capture independent immutable owners from valid structural rows using broad fixture policy.
proc rotationOwner*(records: seq[StateValidator]): ValidatorStateSnapshot =
  let encoded = validatorEntry(ValidatorChapter.Staging, records, rotationRosterConfig())
  assert encoded.error == StateComponentError.None
  let decoded = decodeStateValidators(encoded.value.value, rotationRosterConfig())
  assert decoded.error == StateComponentError.None and decoded.value.consumed ==
      encoded.value.value.len
  decoded.value.value

## Read copied rows back into exact canonical framing, never exposing the owner's mutable storage.
proc rotationBytes*(owner: ValidatorStateSnapshot): seq[byte] =
  let count = validatorCount(owner)
  assert count.error == StateComponentError.None
  var records = newSeq[StateValidator](count.value)
  for i in 0..<records.len:
    records[i] = validatorAt(owner, StateValidatorIndex(uint64(i))).value # Fixed record copy through its owner.
  let encoded = validatorEntry(ValidatorChapter.Staging, records, rotationRosterConfig())
  assert encoded.error == StateComponentError.None
  encoded.value.value
