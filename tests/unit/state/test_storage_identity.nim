# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen full-state identity bytes reject every prefix, octet mutation and foreign chain.
import std/[assertions, syncio]
import ../../../src/storage/database_identity
import ../../../src/codec/bounded

proc main() =
  ## Keep mode/schema/chain checks independent of physical-node or application consumers.
  let limit = ByteLimit(StorageIdentityBytes)
  let chain = default(StorageChainId)
  let identity = fullStateIdentity(chain)
  let encoded = encodeDatabaseIdentity(identity, limit).value
  # Frozen Python hashlib witness covers every schema byte, chain byte and checksum byte.
  let expected = [82'u8, 65, 71, 78, 65, 82, 79, 75, 45, 70, 85, 76, 76, 45, 78, 79,
    68, 69, 83, 45, 86, 49, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 80, 82, 74, 195, 115, 206, 148, 156, 24,
    150, 71, 35, 205, 46, 166, 198, 127, 176, 124, 215, 192, 175, 169, 151, 241,
    124, 144, 50, 233, 242, 221, 159]
  assert encoded == @expected
  for stop in 0..<encoded.len:
    assert decodeDatabaseIdentity(encoded[0..<stop], chain, limit).error ==
        IdentityError.InvalidFormat
  for index in 0..<encoded.len:
    var corrupted = encoded
    corrupted[index] = corrupted[index] xor 1
    assert decodeDatabaseIdentity(corrupted, chain, limit).error != IdentityError.None
  var other = default(array[32, byte])
  other[0] = 1
  assert decodeDatabaseIdentity(encoded, StorageChainId(other), limit).error ==
      IdentityError.WrongChain
  assert encodeDatabaseIdentity(default(DatabaseIdentity), limit).error ==
      IdentityError.Uninitialized
  assert encodeDatabaseIdentity(identity, ByteLimit(StorageIdentityBytes-1)).error ==
      IdentityError.LimitExceeded
  assert decodeDatabaseIdentity(encoded, chain, ByteLimit(StorageIdentityBytes-1)).error ==
      IdentityError.LimitExceeded
  let decoded = decodeDatabaseIdentity(encoded, chain, limit).value
  assert array[32, byte](decoded.chainId) == default(array[32, byte])
  var output = encoded
  output.add(0)
  assert decodeDatabaseIdentity(output, chain, ByteLimit(output.len)).error ==
      IdentityError.InvalidFormat
main()
echo "PASS storage identity: full-mode schema, independent checksum, exact framing and expected chain"
