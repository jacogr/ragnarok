# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent trusted named-field construction for M2 assurance context tests.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import ./nimony_batch_support
import ../../src/codec/assurances as codec_assurances
import ../../src/crypto/primitives as crypto_primitives
import ../../src/crypto/assurance_context as crypto_assurance_context

# Decode only bounded trusted test tokens; no production parsing behavior is hidden here.
proc unhex(text: string): seq[byte] =
  # Dash denotes an explicit empty record or key sequence.
  if text == "-": return @[]
  assert text.len mod 2 == 0 and text.len <= 300000
  result = newSeq[byte](text.len div 2)
  # Validate each complete hexadecimal pair before constructing its byte value.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    for c in pair:
      # The frozen protocol deliberately permits no alternate hexadecimal alphabet.
      assert c in {'0'..'9', 'a'..'f'}
    result[i] = octet(pair)

# Render complete message bytes independently of crypto provider or codec output formatting.
proc hexText(data: openArray[byte]): string =
  # Every transcript is nonempty, but explicit emptiness remains unambiguous in trusted utilities.
  if data.len == 0: return "-"
  result = ""
  # Include all signed bytes, rather than a digest or shortened preview.
  for b in data: result.add(toHex(int(b), 2).toLowerAscii())

# Construct fixed owned fields by name without depending on the previous codec's decoder.
proc records(data: openArray[byte]): seq[Assurance] =
  assert data.len mod 141 == 0
  result = newSeq[Assurance](data.len div 141)
  # Logical test records always include all native bitset storage, including invalid padding.
  for i in 0..<result.len:
    let start = i*141
    # Preserve anchor identity separately from the expected-parent domain.
    for j in 0..<32: result[i].anchor.bytes[j] = data[start+j]
    # Do not mask high or omitted storage bits before testing the production validation.
    for j in 0..<43: result[i].bits.bytes[j] = data[start+32+j]
    result[i].validator = ValidatorIndex(uint16(data[start+75]) or (uint16(data[start+76]) shl 8))
    # Fixed signature encodings are copied without interpreting provider acceptance policy.
    for j in 0..<64: result[i].signature.bytes[j] = data[start+77+j]

# Execute one shared request while checking input stability and failure-only default outcomes.
proc request(parts: seq[string]) =
  # Default checked results must not expose an all-zero transcript or successful count.
  let emptyMessage = default(AssuranceContextResult[AssuranceSigningMessage])
  let emptyCount = default(AssuranceContextResult[VerifiedAssuranceCount])
  assert emptyMessage.error == AssuranceContextError.Uninitialized
  assert emptyCount.error == AssuranceContextError.Uninitialized
  if parts[0] == "M":
    # Direct typed construction keeps message checking independent of the codec encoder/decoder.
    assert parts.len == 4
    let rawParent = unhex(parts[2])
    let rawBits = unhex(parts[3])
    assert rawParent.len == 32 and rawBits.len == 43
    var parentBytes = default(array[32, byte])
    var bits = default(AssuranceBits)
    # The expected parent has a domain independent of record anchors.
    for i in 0..<32: parentBytes[i] = rawParent[i]
    # Keep all native storage visible to canonicality checking.
    for i in 0..<43: bits.bytes[i] = rawBits[i]
    let savedBits = bits
    let checked = assuranceMessage(AssuranceParent(parentBytes), bits, CoreCount(unsigned(
        parts[1])))
    assert bits.bytes == savedBits.bytes
    if checked.error == AssuranceContextError.None:
      # Only the success branch permits access to its owned transcript bytes.
      echo hexText(array[45, byte](checked.value))
    else:
      # Failure exposes only a stable typed reason.
      echo ($checked.error).toLowerAscii()
  else:
    # Verification receives an explicit configured validator-key mapping.
    assert parts[0] == "V" and parts.len == 6
    let config = AssuranceConfig(cores: CoreCount(unsigned(parts[1])),
                                 validators: ValidatorCount(unsigned(parts[2])))
    let rawParent = unhex(parts[3])
    let rawKeys = unhex(parts[4])
    assert rawParent.len == 32 and rawKeys.len mod 32 == 0
    var parentBytes = default(array[32, byte])
    # Parent bytes are constructed independently from every record's declared anchor.
    for i in 0..<32: parentBytes[i] = rawParent[i]
    var keys = newSeq[EdPublicKey](rawKeys.len div 32)
    # Existing public imports establish fixed key ownership without a new provider or policy.
    for i in 0..<keys.len:
      let imported = importPublicKey(rawKeys.toOpenArray(i*32, i*32+31))
      assert imported.error == CryptoError.None
      keys[i] = imported.value
    let values = records(unhex(parts[5]))
    let savedValues = values
    let savedKeys = keys
    let checked = verifyAssurances(values, config, AssuranceParent(parentBytes), keys)
    # Inspect all original native fields after the synchronous borrowed call.
    for i in 0..<values.len:
      assert values[i].anchor.bytes == savedValues[i].anchor.bytes
      assert values[i].bits.bytes == savedValues[i].bits.bytes
      assert uint16(values[i].validator) == uint16(savedValues[i].validator)
      assert values[i].signature.bytes == savedValues[i].signature.bytes
    # A provider may borrow public encodings but must not mutate the caller's key table.
    for i in 0..<keys.len: assert array[32, byte](keys[i]) == array[32, byte](savedKeys[i])
    if checked.error == AssuranceContextError.None:
      # Successful count certifies only this context/signature check.
      echo "ok " & $uint64(checked.value)
    else:
      # No verified count may be read from this failed branch.
      echo ($checked.error).toLowerAscii()

# A single native process handles the complete frozen test corpus.
proc main() =
  assert paramCount() == 1
  # File input belongs to the trusted harness, not to production crypto code.
  for line in lines(paramStr(1)):
    if line.len == 0:
      # Ignore the batch file's trailing newline.
      continue
    request(line.splitWhitespace())

main()
