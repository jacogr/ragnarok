# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent header.tex projections include rich published data, every family and multi-byte counts.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/crypto/extrinsic_commitment
import ../../../src/codec/[block_codec, bounded, composite, header, disputes]

## Test-only primitive refusal preserves successful production digests.
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
## Refuse after a complete prefix of blob/report/family hashes.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Every default/preflight refusal must reach zero hash calls.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Trusted fixture octets are exact, without production parsing or guessed source buffers.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[i*2..i*2+1], result[i]) == 2 # Complete trusted hexadecimal octets only.

## Decimal fixture counts are complete before native narrowing.
proc number(text: string): int =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len and value <= uint64(high(int))
  int(value)

## Full-profile structural capture keeps explicit record/blob and complete-frame ceilings.
proc policy(): FrameConfig =
  fullFrameConfig(ByteLimit(2000000), PreimageLimits(items: ElementLimit(10000),
    perBlob: ByteLimit(2000000), totalBlobBytes: ByteLimit(2000000)))

## All independent answers must match, and every primitive refusal must return no partial root.
proc cases(text: string) =
  let lines = text.splitLines()
  assert lines.len == 10
  for index in 0..<9:
    let fields = lines[index].splitWhitespace()
    assert fields.len == 5
    let raw = unhex(fields[1])
    let parsed = decodeExtrinsic(raw, policy())
    if fields[0] == "published-rejected-order":
      assert parsed.error == FrameError.InvalidComponent # Preserve the codec fixture's original invalid verdict order as negative evidence.
      assert parsed.cause.kind == ComponentKind.Disputes and parsed.cause.disputeError ==
          DisputeError.NonCanonical
      continue # Only the explicitly labelled authored counterpart supplies valid rich input.
    assert parsed.error == FrameError.None and parsed.value.consumed == raw.len
    let owner = parsed.value.owner
    let expected = unhex(fields[2])
    let projected = number(fields[3])
    let attempts = number(fields[4])
    let ceiling = max(projected, raw.len)
    reset(0)
    let outcome = extrinsicCommitment(owner, ByteLimit(uint64(ceiling)))
    assert outcome.error == ExtrinsicCommitmentError.None and hashes() == cint(attempts)
    assert array[32, byte](outcome.value) == expected # The independent oracle uses hashlib and separate field serializers.
    reset(0)
    assert extrinsicCommitment(owner, ByteLimit(uint64(ceiling-1))).error ==
      ExtrinsicCommitmentError.LimitExceeded and hashes() == 0
    for prefix in [0, attempts div 2, attempts-1]:
      refuseAfter(cint(prefix))
      let refused = extrinsicCommitment(owner, ByteLimit(uint64(ceiling)))
      assert refused.error == ExtrinsicCommitmentError.BackendFailure
      assert hashes() == cint(prefix+1) # Includes final digest refusal after every family completed.
    reset(0)
    var saved = newSeq[byte](raw.len)
    assert encodeOwnedExtrinsic(owner, saved).value == raw.len and saved ==
        raw # Neither hashing nor refusal mutates captured components.
  reset(0)
  assert extrinsicCommitment(default(OwnedExtrinsic), ByteLimit(100)).error ==
      ExtrinsicCommitmentError.InvalidOwner
  assert hashes() == 0

try:
  cases(readFile(getEnv("RAGNAROK_EXTRINSIC_COMMITMENT"))) # Missing source/evidence must fail rather than silently skip rich families.
except:
  quit(2) # An incomplete oracle corpus cannot satisfy the native profile.
echo "PASS extrinsic commitment: rich families, projected budgets and primitive rollback"
