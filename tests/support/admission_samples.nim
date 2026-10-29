# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Small authored complete-root unions support independent staged-admission refusal and ownership checks.
import ./storage_samples
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/node/records as node_records
import ../../src/storage/record_codec
import ../../src/storage/node/repository as node_repository
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../src/codec/bounded

type AdmissionFixture* = object ## Detached test image retains no live mutable repository or private-cell authority.
  image*: RepositoryImage
  limits*: RepositoryLimits
proc admissionFixture*(): AdmissionFixture =
  ## Retain the first and third roots while excluding the intermediate branch/value records from the image.
  let limits = storageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  let c = storageTrie(10)
  var owner = newNodeRepository(limits)
  let first = owner.publish(owner.snapshot.value, exportFullTrie(a,
      limits.codec.records).value).value
  let second = owner.publish(first, exportTrieChanges(a, b, limits.codec.records).value).value
  let third = owner.publish(second, exportTrieChanges(b, c, limits.codec.records).value).value
  let selected = selectRepositoryRoots(third, [first.commitment.root, third.commitment.root],
      ElementLimit(2)).value
  AdmissionFixture(image: exportRepositoryImage(selected, limits.codec.records, ElementLimit(
      2)).value,
    limits: limits)
proc admissionBody*(source: AdmissionFixture): seq[byte] =
  ## Serialization proves local physical integrity only; complete image admission remains independent.
  encodeRecordCollection(source.image.collection, source.limits.codec).value
proc decodeAdmission*(source: AdmissionFixture, input: openArray[byte]): RepositoryResult[
    NodeRepository] =
  ## Bind every checked root/generation claim to the same finite authored image and inherited policy.
  decodeRepositoryImage(input, source.image.generation, source.image.commitment, source.image.roots,
    source.limits, ElementLimit(2), ByteLimit(500000))
proc compareAdmissionRecords*(a, b: TrieRecord): int =
  ## Author canonical physical order without importing private codec comparators or trusted tokens.
  let left = array[32, byte](a.digest)
  let right = array[32, byte](b.digest)
  for index in 0..<32:
    if left[index] < right[index]: return -1 # The first unequal complete identity byte decides order.
    if left[index] > right[index]: return 1
  0
