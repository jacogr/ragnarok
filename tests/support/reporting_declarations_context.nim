# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded test-authored logical identities qualify actual candidate values without supplying any posterior values.
import std/assertions
import ../../src/state/store
import ../../src/codec/[bounded, state_layout, state_accounts, state_service_values, state_requests, state_composition]

type
  DeclaredHash* = object
    ## One immutable-by-convention input hash and its explicitly bounded request lengths.
    hash*: ServicePreimageHash
    lengths*: seq[uint32]
  DeclaredService* = object
    ## Logical identity declaration only; actual metadata/storage/preimages/histories are read from the native owner.
    service*: ServiceIndex
    storage*: seq[seq[byte]]
    hashes*: seq[DeclaredHash]
  DeclarationCursor = object
    ## A private checked cursor never outlives its owned test packet.
    bytes: seq[byte]
    offset: int

proc take(cursor: var DeclarationCursor, size: int): seq[byte] =
  ## Prove each raw extent before allocation/copy; negative or truncated lengths fail the test transport.
  assert size >= 0 and cursor.offset <= cursor.bytes.len and size <= cursor.bytes.len-cursor.offset, "inventory/InvalidDeclaration"
  result = newSeq[byte](size)
  for index in 0..<size:
    result[index] = cursor.bytes[cursor.offset+index]
  cursor.offset += size

proc word(cursor: var DeclarationCursor, size: int): uint32 =
  ## Read only the declared E2/E4 transport words, distinct from production JAM decoding.
  assert size in [2, 4]
  let bytes = cursor.take(size)
  result = 0
  for index in 0..<size:
    result = result or (uint32(bytes[index]) shl (8*index))

proc decodeDeclarations*(bytes: seq[byte]): seq[DeclaredService] =
  ## Finite identity/key/hash/length counts precede allocation and duplicate identities never become authority.
  assert bytes.len <= 16384
  var cursor = DeclarationCursor(bytes: bytes, offset: 0)
  let count = cursor.word(2)
  assert count <= 16, "inventory/InvalidDeclaration"
  result = @[]
  for index in 0..<int(count):
    let id = ServiceIndex(cursor.word(4))
    for prior in result:
      assert uint32(prior.service) != uint32(id)
    var service = DeclaredService(service: id, storage: @[], hashes: @[])
    let keys = cursor.word(2)
    assert keys <= 16
    for keyIndex in 0..<int(keys):
      let length = cursor.word(2)
      assert length <= 1024
      let key = cursor.take(int(length))
      for prior in service.storage:
        assert prior != key
      service.storage.add(key)
    let hashes = cursor.word(2)
    assert hashes <= 64
    for hashIndex in 0..<int(hashes):
      let raw = cursor.take(32)
      var fixed = default(array[32, byte])
      for at in 0..<32:
        fixed[at] = raw[at]
      let hash = ServicePreimageHash(fixed)
      for prior in service.hashes:
        assert array[32, byte](prior.hash) != array[32, byte](hash)
      let lengths = cursor.word(2)
      assert lengths <= 16
      var row = DeclaredHash(hash: hash, lengths: @[])
      for lengthIndex in 0..<int(lengths):
        let length = cursor.word(4)
        assert length < high(uint32)-1
        for prior in row.lengths:
          assert prior != length
        row.lengths.add(length)
      service.hashes.add(row)
    result.add(service)
  assert cursor.offset == cursor.bytes.len

proc declaredServices*(source: StateStoreSnapshot, declarations: openArray[DeclaredService]): seq[StateService] =
  ## Capture only actual selected values at authored identities; exact-map qualification still rejects every undeclared entry.
  result = @[]
  let histories = RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13))
  for declaration in declarations:
    let metadata = source.lookup(chapterServiceKey(StateChapter(255), declaration.service))
    if metadata.error == StateStoreError.MissingKey:
      continue # Future/refused creations and actually retired accounts have no live namespace.
    assert metadata.error == StateStoreError.None
    let decoded = decodeServiceMetadata(metadata.value.bytes, ByteLimit(105))
    assert decoded.error == ServiceMetadataError.None and decoded.value.consumed ==
        metadata.value.bytes.len
    var service = StateService(service: declaration.service, metadata: decoded.value.metadata)
    for key in declaration.storage:
      let entry = source.lookup(serviceStorageKey(declaration.service, key, ByteLimit(1024)).value)
      if entry.error == StateStoreError.None:
        service.storage.add(StateStorageItem(key: key, value: entry.value.bytes))
      else:
        assert entry.error == StateStoreError.MissingKey # Other lookup errors cannot be masked as absent data.
    for row in declaration.hashes:
      let entry = source.lookup(servicePreimageKey(declaration.service, row.hash, ByteLimit(32)).value)
      if entry.error == StateStoreError.None:
        service.preimages.add(StatePreimageItem(hash: row.hash, value: entry.value.bytes))
      else:
        assert entry.error == StateStoreError.MissingKey
      for length in row.lengths:
        let request = source.lookup(serviceRequestKey(declaration.service, row.hash, RequestLength(
            length), ByteLimit(32)).value)
        if request.error == StateStoreError.None:
          let parsed = decodeRequestHistory(request.value.bytes, histories)
          assert parsed.error == RequestError.None and parsed.value.consumed ==
              request.value.bytes.len
          service.requests.add(StateRequestItem(hash: row.hash, length: RequestLength(length),
              history: parsed.value.history))
        else:
          assert request.error == StateStoreError.MissingKey
    result.add(service)
