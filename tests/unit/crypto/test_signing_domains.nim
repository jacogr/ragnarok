# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External tiny/full credentials bind the exact ASCII token bytes independently of local signing code.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/crypto/[assurance_context, guarantee, primitives]
import ../../../src/codec/assurances

## Parse trusted fixture octets exactly; malformed transport cannot count as signature rejection.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet = 0'u8
    assert parseHex(text[2*i..2*i+1], octet) == 2 # Require the whole octet.
    result[i] = octet

## Read small trusted nonnegative profile/cardinality values with complete consumption.
proc number(text: string): int =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len and value <= uint64(high(int))
  int(value)

## Preserve copied hash/public-key identities without shared transport storage.
proc fixed(text: string): array[32, byte] =
  let bytes = unhex(text)
  assert bytes.len == 32
  result = default(array[32, byte])
  for i in 0..<32: result[i] = bytes[i] # Fixed-width copy only.

## Actual published credentials must succeed on ASCII bytes and fail when the old dollar byte is prepended.
proc credential(key: EdPublicKey, signature, message: seq[byte]) =
  let imported = importSignature(signature)
  assert imported.error == CryptoError.None
  assert message.len == 45 and message[0] == byte('j')
  assert verify(key, imported.value, message)
  var old = @[byte('$')]
  for octet in message: old.add octet # Preserve all transcript bytes after the rejected dollar prefix.
  assert not verify(key, imported.value, old) # No alternate-domain fallback is permitted.
  var mutated = message
  mutated[mutated.len-1] = mutated[mutated.len-1] xor 1'u8
  assert not verify(key, imported.value, mutated) # Identity digest bytes remain fully signed.

## Consume all four pinned successful STF sources, retaining source credentials rather than signing replacements.
proc published(text: string) =
  let lines = text.splitLines()
  var cursor = 0
  var cases = 0
  var checked = 0
  while cursor < lines.len-1:
    let fields = lines[cursor].splitWhitespace()
    inc cursor
    if fields[0] == "A":
      # Each assurance selects a public key by validator identity in the complete upstream table.
      let cores = number(fields[1])
      let validators = number(fields[2])
      let parent = fixed(fields[3])
      let rawKeys = unhex(fields[4])
      assert rawKeys.len == validators*32
      var keys = newSeq[EdPublicKey](validators)
      for i in 0..<validators:
        let imported = importPublicKey(rawKeys.toOpenArray(i*32, i*32+31))
        assert imported.error == CryptoError.None
        keys[i] = imported.value
      for i in 0..<number(fields[5]):
        let row = lines[cursor].splitWhitespace()
        inc cursor
        let index = number(row[0])
        assert index < validators
        let rawBits = unhex(row[1])
        assert rawBits.len == (cores+7) div 8
        var value = default(Assurance)
        value.anchor.bytes = parent
        value.validator = ValidatorIndex(index)
        for j in 0..<rawBits.len: value.bits.bytes[j] = rawBits[j] # Fixed profile width without a count prefix.
        let signature = unhex(row[2])
        assert signature.len == 64
        for j in 0..<64: value.signature.bytes[j] = signature[j] # Original upstream credential.
        let expected = unhex(row[3])
        let message = assuranceMessage(AssuranceParent(parent), value.bits, CoreCount(uint64(cores)))
        assert message.error == AssuranceContextError.None
        let bytes = array[45, byte](message.value)
        assert @bytes == expected
        credential(keys[index], signature, expected)
        let verified = verifyAssurances(@[value], AssuranceConfig(cores: CoreCount(uint64(cores)),
            validators: ValidatorCount(uint64(validators))), AssuranceParent(parent), keys)
        assert verified.error == AssuranceContextError.None and uint64(verified.value) == 1
        inc checked
    else:
      # Report credentials independently bind the complete canonical report encoding and its transcript.
      assert fields[0] == "G"
      let report = unhex(fields[1])
      let message = guaranteeMessage(report)
      assert message.error == CryptoError.None
      let bytes = array[45, byte](message.value)
      for i in 0..<number(fields[2]):
        let row = lines[cursor].splitWhitespace()
        inc cursor
        let imported = importPublicKey(unhex(row[0]))
        assert imported.error == CryptoError.None
        let expected = unhex(row[2])
        assert @bytes == expected
        credential(imported.value, unhex(row[1]), expected)
        inc checked
    inc cases
  assert cursor == lines.len-1 and cases == 4 and checked ==
      1035 # Preserve all upstream credentials, both domains and both profiles.

try:
  published(readFile(getEnv("RAGNAROK_SIGNING_DOMAINS"))) # Fixture I/O is explicit infrastructure failure.
except:
  quit(2) # Missing/malformed fixtures cannot count as protocol conformance.
echo "PASS signing domains: published tiny/full credentials, exact ASCII tokens and old-domain rejection"
