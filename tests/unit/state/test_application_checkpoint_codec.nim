# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_codec_arc_release"}

## Exact independently encoded metadata bytes, every cut/tamper and full profile invariants gate local checkpoint context.
import std/[assertions, envvars, syncio]
import ../../../src/app/checkpoint_identity
import ../../../src/codec/bounded
import ../../../src/crypto/primitives
import ../../support/[application_checkpoint_context, arc_evidence]
proc fixtureBytes(): seq[byte] {.raises.} =
  ## A pinned byte fixture comes from Python hashlib plus the original independent RPC root/hash goldens.
  let path = getEnv("RAGNAROK_APPLICATION_CHECKPOINT_IDENTITY")
  assert path.len > 0
  let text = readFile(path)
  result = newSeq[byte](text.len)
  for index, octet in text:
    result[index] = byte(octet) # Preserve binary bytes without text/hex normalization.
proc copied(bytes: seq[byte]): seq[byte] =
  ## Tampering never mutates a retained expected fixture through shared test storage.
  result = newSeq[byte](bytes.len)
  for index, octet in bytes:
    result[index] = octet # Start every malformed case from the independently supplied exact input.
proc cycle(bytes: seq[byte], identity: ApplicationCheckpointIdentity) =
  ## Repeated local codecs retain neither temporary buffers nor source application graphs.
  assert encodeApplicationCheckpointIdentity(identity, ByteLimit(238)).value == bytes
  assert sameApplicationCheckpoint(decodeApplicationCheckpointIdentity(bytes, ByteLimit(238)).value, identity)
proc main() {.raises.} =
  ## Initialized decoding establishes format only; a recomputed checksum cannot establish caller trust.
  let owner = checkpointFixture()
  let identity = captureApplicationCheckpointIdentity(owner).value
  let bytes = fixtureBytes()
  assert bytes.len == ApplicationCheckpointIdentityBytes
  assert encodeApplicationCheckpointIdentity(identity, ByteLimit(238)).value == bytes
  assert sameApplicationCheckpoint(decodeApplicationCheckpointIdentity(bytes, ByteLimit(238)).value, identity)
  let absent = default(ApplicationCheckpointIdentity)
  assert encodeApplicationCheckpointIdentity(absent, ByteLimit(238)).error ==
      ApplicationCheckpointIdentityError.Uninitialized
  for extent in 0..<bytes.len:
    assert decodeApplicationCheckpointIdentity(bytes.toOpenArray(0, extent - 1), ByteLimit(
        238)).error == ApplicationCheckpointIdentityError.InvalidFormat
    assert encodeApplicationCheckpointIdentity(identity, ByteLimit(uint64(extent))).error ==
        ApplicationCheckpointIdentityError.LimitExceeded
  for index in 0..<bytes.len:
    var corrupt = copied(bytes)
    corrupt[index] = corrupt[index] xor 1
    assert decodeApplicationCheckpointIdentity(corrupt, ByteLimit(238)).error !=
        ApplicationCheckpointIdentityError.None # No field or checksum byte is ignored.
  var extra = copied(bytes)
  extra.add(0)
  assert decodeApplicationCheckpointIdentity(extra, ByteLimit(1000)).error ==
      ApplicationCheckpointIdentityError.InvalidFormat
  assert decodeApplicationCheckpointIdentity(bytes, ByteLimit(237)).error ==
      ApplicationCheckpointIdentityError.LimitExceeded
  var altered = copied(bytes)
  altered[16] = altered[16] xor 1
  let digest = array[32, byte](blake2b256(altered.toOpenArray(0, 205)).value)
  for index in 0..<32:
    altered[206 + index] = digest[index] # An attacker can recompute an integrity checksum; identity comparison still refuses another header.
  let untrusted = decodeApplicationCheckpointIdentity(altered, ByteLimit(238)).value
  assert not sameApplicationCheckpoint(identity, untrusted)
  var invalid = copied(bytes)
  invalid[108] = 0
  invalid[109] = 0 # Core population occupies the two bytes following three E8 deposit fields; default population is invalid.
  let repaired = array[32, byte](blake2b256(invalid.toOpenArray(0, 205)).value)
  for index in 0..<32:
    invalid[206 + index] = repaired[index] # Even valid integrity cannot authorize an invalid complete profile.
  assert decodeApplicationCheckpointIdentity(invalid, ByteLimit(238)).error ==
      ApplicationCheckpointIdentityError.InvalidParameters
  cycle(bytes, identity)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bytes, identity) # Exact native allocator occupancy is measured after warmup.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_codec", 1000, before, after)
  echo "PASS application checkpoint codec: independent bytes, exact bounds, integrity and untrusted metadata"
try:
  main() # Native or fixture errors cannot be accepted as zero successful cases.
except:
  quit(2)
