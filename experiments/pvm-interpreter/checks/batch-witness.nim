# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Independent public withPage reference for batched immutable replacement, ceilings and retained owners.
import std/[assertions, syncio]
import ../src/pvm/machine

proc same(left, right: Memory, indices: openArray[uint32]) =
  ## Compare every mapped byte/access plus absent pages; no raw owner pointers enter the test.
  for index in indices:
    let a = pageImage(left, PageIndex(index))
    let b = pageImage(right, PageIndex(index))
    assert a.error == MachineError.None and b.error == MachineError.None
    assert a.value.bytes == b.value.bytes and a.value.access == b.value.access

proc detached(source: Memory, replacements: openArray[PageImage]): Memory =
  ## A returned owner must outlive the helper's temporary replacement vectors and page captures.
  let updated = withReplacedPages(source, replacements)
  assert updated.error == MachineError.None
  updated.value

var cases = 0
for shape in 0..<2:
  let indices = if shape == 0: @[0'u32, 1, 63, 64, 1048575] else: @[16'u32, 32, 128, 1024, 65536]
  var images: seq[PageImage] = @[]
  for slot in 0..<indices.len:
    # All access tags carry observable retained bytes, including inaccessible pages.
    var image = PageImage(index: PageIndex(indices[slot]), access: PageAccess(slot mod 3))
    for at in 0..<4096: image.bytes[at] = byte((slot*37+at*17) mod 251)
    images.add(image)
  let source = captureMemory(images, PageLimit(5)).value
  let alias = source
  for mask in 0..<32:
    var current = source
    var expected = source
    var retained: seq[Memory] = @[source]
    var expectedRetained: seq[Memory] = @[source]
    for epoch in 0..<4:
      # Reuse prior published roots through later epochs; every subset includes sparse first/last combinations.
      var replacements: seq[PageImage] = @[]
      for slot in 0..<indices.len:
        if (mask and (1 shl slot)) != 0:
          var image = pageImage(current, PageIndex(indices[slot])).value
          for at in 0..<4096: image.bytes[at] = byte((slot*31+epoch*19+at*3+1) mod 253)
          replacements.add(image)
          let changed = withPage(expected, image)
          assert changed.error == MachineError.None
          expected = changed.value
      let prior = current
      let updated = withReplacedPages(current, replacements)
      assert updated.error == MachineError.None
      current = updated.value
      let identityDelta = changedMemoryPages(prior, current)
      assert identityDelta.error == MachineError.None and identityDelta.value.len ==
          replacements.len
      same(current, expected, indices)
      same(detached(retained[retained.len-1], replacements), expected, indices)
      for i in 0..<replacements.len:
        # Caller mutation after capture must not change any published byte.
        replacements[i].bytes[0] = replacements[i].bytes[0] xor 255'u8
      same(current, expected, indices)
      retained.add(current)
      expectedRetained.add(expected)
      for i in 0..<retained.len: same(retained[i], expectedRetained[i], indices)
      same(source, alias, indices)
      let full = withPage(current, PageImage(index: PageIndex(65535), access: PageAccess.ReadWrite))
      assert full.error == MachineError.LimitExceeded
      inc cases
  let first = images[0]
  var missing = first
  missing.index = PageIndex(65535)
  var invalid = first
  invalid.index = PageIndex(1048576)
  var changedAccess = first
  changedAccess.access = PageAccess.ReadWrite
  assert withReplacedPages(source, [first, missing]).error == MachineError.InvalidRange
  assert withReplacedPages(source, [first, invalid]).error == MachineError.InvalidPage
  assert withReplacedPages(source, [first, first]).error == MachineError.UnsortedPages
  assert withReplacedPages(source, [images[4], first]).error == MachineError.UnsortedPages
  assert withReplacedPages(source, [changedAccess]).error == MachineError.InvalidRange
  same(source, alias, indices)
  for i in 0..<images.len:
    let unchanged = pageImage(source, images[i].index).value
    assert unchanged.bytes == images[i].bytes and unchanged.access == images[i].access
  var roomy = withReplacedPages(captureMemory(images, PageLimit(8)).value, [first]).value
  for index in [70000'u32, 70001, 70002]:
    # A batch must preserve spare page capacity too, rather than silently lowering the local ceiling.
    let added = withPage(roomy, PageImage(index: PageIndex(index), access: PageAccess.ReadWrite))
    assert added.error == MachineError.None
    roomy = added.value
  assert withPage(roomy, PageImage(index: PageIndex(70003))).error == MachineError.LimitExceeded
let empty = captureMemory([], PageLimit(0)).value
let copiedEmpty = withReplacedPages(empty, [])
assert copiedEmpty.error == MachineError.None
assert withPage(copiedEmpty.value, PageImage(index: PageIndex(0))).error ==
    MachineError.LimitExceeded
assert withReplacedPages(empty, [PageImage(index: PageIndex(0))]).error == MachineError.InvalidRange
assert withReplacedPages(default(Memory), []).error == MachineError.InvalidOwner
assert withReplacedPages(default(Memory), [PageImage(index: PageIndex(1048576))]).error ==
    MachineError.InvalidOwner
# Equal bytes are not an ownership proof; recreated pages must still appear in the copied delta.
let mappingIndices = [16'u32, 32'u32, 1048575'u32]
var mappingImages: seq[PageImage] = @[]
for slot in 0..<mappingIndices.len:
  var image = PageImage(index: PageIndex(mappingIndices[slot]), access: PageAccess.ReadWrite)
  for at in 0..<4096: image.bytes[at] = byte((slot*19+at*7) mod 251)
  mappingImages.add(image)
let beforeMapping = captureMemory(mappingImages, PageLimit(4)).value
let heldMapping = beforeMapping
let recreated = captureMemory(mappingImages, PageLimit(4)).value
let recreatedDelta = changedMemoryPages(beforeMapping, recreated)
assert recreatedDelta.error == MachineError.None and recreatedDelta.value.len == 3
assert changedMemoryPages(beforeMapping, heldMapping).value.len == 0
var metadataCases = 0
for slot in 0..<mappingIndices.len:
  for access in [PageAccess.Inaccessible, PageAccess.ReadOnly]:
    # A legitimate early byte change must not hide a later permission mismatch or publish a prefix.
    var first = mappingImages[0]
    first.bytes[0] = first.bytes[0] xor 17
    let early = withPage(beforeMapping, first).value
    var mismatched = mappingImages[slot]
    mismatched.access = access
    let posterior = withPage(early, mismatched).value
    assert changedMemoryPages(beforeMapping, posterior).error == MachineError.InvalidRange
    same(beforeMapping, heldMapping, mappingIndices)
    inc metadataCases
assert metadataCases == 6
assert changedMemoryPages(default(Memory), beforeMapping).error == MachineError.InvalidOwner
assert changedMemoryPages(beforeMapping, default(Memory)).error == MachineError.InvalidOwner
echo "PASS delta identity / distinct equal-byte owners / six metadata refusals / shared-prefix and retained-source checks"
assert cases == 256
echo "PASS batch replacements /", cases, " subset-epoch cases / sequential oracle / all bytes and access / retained owners / caller mutation / ceilings / atomic refusals"
