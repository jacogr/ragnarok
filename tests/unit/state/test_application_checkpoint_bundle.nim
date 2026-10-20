# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_checkpoint_bundle_arc_release"}

## The independently serialized full application envelope preserves exact aggregate ceilings and source ownership.
import std/[assertions, envvars, syncio]
import ../../../src/app/[chain, checkpoint_codec, checkpoint_identity]
import ../../../src/codec/bounded
import ../../support/[application_checkpoint_context, arc_evidence]
proc fixtureBytes(): seq[byte] {.raises.} =
  ## The pinned golden concatenates independent metadata and exact original sorted serialized-map entries.
  let path = getEnv("RAGNAROK_APPLICATION_CHECKPOINT_BUNDLE")
  assert path.len > 0
  let text = readFile(path)
  result = newSeq[byte](text.len)
  for index, octet in text:
    result[index] = byte(octet) # Binary bytes are not reinterpreted as text or hex.
proc cycle(owner: ApplicationChain, expected: seq[byte]) =
  ## All temporary encoded identity/checkpoint buffers retire between calls.
  assert encodeApplicationCheckpoint(owner, ByteLimit(uint64(expected.len))).value == expected
proc main() {.raises.} =
  ## Exact complete bytes agree with an independent encoder; every short aggregate budget refuses without a prefix payload.
  let owner = checkpointFixture()
  let expected = fixtureBytes()
  let absent = default(ApplicationChain)
  let refused = encodeApplicationCheckpoint(absent, ByteLimit(high(uint64)))
  assert refused.error == ApplicationCheckpointError.IdentityFailure
  assert refused.identityError == ApplicationCheckpointIdentityError.MissingHead
  assert encodeApplicationCheckpoint(owner, ByteLimit(high(uint64))).value == expected
  for extent in 0..<expected.len:
    assert encodeApplicationCheckpoint(owner, ByteLimit(uint64(extent))).error ==
        ApplicationCheckpointError.LimitExceeded # Metadata overhead cannot silently exceed the caller's whole-envelope policy.
  for variant in [CheckpointFixtureVariant.Header, CheckpointFixtureVariant.Profile,
      CheckpointFixtureVariant.State]:
    let different = checkpointFixture(variant)
    assert encodeApplicationCheckpoint(different, ByteLimit(high(uint64))).value !=
        expected # All context or complete-map changes remain observable in persisted bytes.
  cycle(owner, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(owner, expected) # Encoded bytes retain no canonical graph after release.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_checkpoint_bundle", 1000, before, after)
  echo "PASS application checkpoint bundle: independent full bytes, aggregate bounds and detached encoding"
try:
  main() # Missing fixture or native setup cannot yield a successful empty corpus.
except:
  quit(2)
