# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable GP 0.8.0 fetch-parameter snapshots. Fixed-width decoding owns every value;
## it does not initialize genesis state or infer validator-dependent settings.
##
## Exposes Parameter field identifiers, immutable Parameters and guarded ParameterResult accessors,
## plus fixed-width encoding, byte/hex decoders and explicit host-selected expiry interpretation.

# Field order and widths follow Appendix B's fetch(0) tuple exactly.
type
  Parameter* = enum
    depositPerItem, depositPerByte, depositPerAccount, coreCount, minTurnaroundPeriod,
    epochPeriod, maxAccumulateGas, maxIsAuthorizedGas, maxRefineGas, blockGasLimit,
    recentBlockCount, maxWorkItems, maxDependencies, maxTicketsPerBlock, maxLookupAnchorAge,
    authWindow, slotPeriodSec, authQueueLen, rotationPeriod, maxExtrinsics, availabilityTimeout,
    maxAuthorizerCodeSize, maxInput, maxServiceCodeSize, maxImports, maxReportElectiveData,
    transferMemoSize, maxExports, epochTailStart
  ExpungePeriod* = distinct uint64 ## A configured expiry duration is distinct from a lookup-anchor age.
  Parameters* = object ## A successful snapshot owns fixed-size scalar data and exposes no mutable storage.
    numbers: array[29, uint64]
    explicitExpunge: bool # Host-selected interpretation is immutable metadata, never a fetch(0) wire field.
  ParameterError* = enum wrongSize, invalidConfiguration ## Decoding failure is distinct from any valid numeric field value.
  ParameterResult* = object ## A default result is failure; unsuccessful decoding never exposes partial parameter values.
    case success: bool
    of true:
      snapshot: Parameters
    of false:
      reason: ParameterError

const ParameterBytes* = 122
const Widths: array[Parameter, int] = [8, 8, 8, 2, 4, 4, 8, 8, 8, 8, 2, 2, 2, 2, 4,
    2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4]

func unavailableParameters*(): ParameterResult =
  ## Represent absent configuration without constructing or exposing a parameter snapshot.
  ParameterResult(success: false, reason: wrongSize)

func ok*(decoded: ParameterResult): bool =
  ## Read-only result selection precedes extraction of an immutable owned snapshot.
  decoded.success

func value*(decoded: ParameterResult): Parameters {.requires: decoded.success.} =
  ## Copy the complete fixed-size snapshot only after successful decoding.
  decoded.snapshot

func error*(decoded: ParameterResult): ParameterError {.requires: not decoded.success.} =
  ## Explain a failed decode without exposing a partial snapshot.
  decoded.reason

func get*(parameters: Parameters, field: Parameter): uint64 =
  ## Return one scalar by nominal field identity, with no borrow into the original byte buffer.
  parameters.numbers[ord(field)]

func valid*(parameters: Parameters): bool =
  ## Check the existing population/clock invariants, including rejection of a default snapshot.
  ## Other fields retain the exact configured values; this is not full chain-profile validation.
  parameters.get(coreCount) >= 2 and parameters.get(epochPeriod) != 0 and
    parameters.get(slotPeriodSec) != 0 and parameters.get(rotationPeriod) != 0 and
    parameters.get(epochTailStart) <= parameters.get(epochPeriod)

func withExplicitExpungePeriod*(parameters: Parameters): ParameterResult =
  ## Select the configured D field explicitly; callers retain the unchanged original snapshot and wire tuple.
  if not parameters.valid:
    return ParameterResult(success: false, reason: invalidConfiguration)
  var selected = parameters
  selected.explicitExpunge = true
  ParameterResult(success: true, snapshot: selected)

func hasExplicitExpungePeriod*(parameters: Parameters): bool =
  ## Identify process-local interpretation metadata before any durable profile encoding.
  parameters.explicitExpunge

func expungePeriod*(parameters: Parameters): ExpungePeriod {.requires: parameters.valid.} =
  ## Normal profiles retain the pinned lookup safety margin; explicit presets use their configured D.
  ## Both fields are decoded E4 values, so widened addition cannot overflow uint64.
  if parameters.explicitExpunge:
    ExpungePeriod(parameters.get(minTurnaroundPeriod))
  else:
    ExpungePeriod(parameters.get(maxLookupAnchorAge) + 4800)

func sameParameterProfile*(left, right: Parameters): bool =
  ## Complete immutable execution identity includes interpretation metadata as well as every numeric field.
  if not left.valid or not right.valid or left.explicitExpunge != right.explicitExpunge:
    return false
  for field in low(Parameter)..high(Parameter):
    # Equal fetch tuples alone cannot mix different expiry interpretations within a retained chain.
    if left.get(field) != right.get(field): return false
  true

proc encodeParameters*(parameters: Parameters): array[ParameterBytes, byte]
    {.requires: parameters.valid.} =
  ## Re-emit a validated immutable snapshot in fetch(0) field order, without allocating or borrowing.
  ## Private scalar storage can only originate from width-checked decoding; no narrowing is possible.
  result = default(array[ParameterBytes, byte])
  var offset = 0
  for field in low(Parameter)..high(Parameter):
    # Every field uses its declared fixed little-endian width, never compact encoding.
    let number = parameters.get(field)
    for i in 0..<Widths[field]:
      # Widths are at most eight and sum to the fixed 122-byte output extent.
      result[offset + i] = byte((number shr (8 * i)) and 255)
    offset += Widths[field]

proc decodeParameters*(bytes: openArray[byte]): ParameterResult =
  ## Decode the exact GP tuple; reject every truncated or extended record before reading a byte.
  if bytes.len != ParameterBytes: return ParameterResult(success: false)
  var parameters = default(Parameters)
  var offset = 0
  for field in low(Parameter)..high(Parameter): # All fixed widths sum to the validated extent; no variable allocation occurs.
    if offset < 0 or Widths[field] > bytes.len - offset: return ParameterResult(success: false)
    var number = 0'u64
    for i in 0..<Widths[field]: # Little-endian shifts never exceed 56 bits.
      if offset + i >= bytes.len: return ParameterResult(success: false)
      number = number or (uint64(bytes[offset + i]) shl (8 * i))
    parameters.numbers[ord(field)] = number
    offset += Widths[field]
  # Reject unusable population/clock settings; do not substitute a canonical network profile.
  if not parameters.valid:
    return ParameterResult(success: false, reason: invalidConfiguration)
  ParameterResult(success: true, snapshot: parameters)

proc decodeParametersHex*(text: string): ParameterResult =
  ## JIP-4 uses unprefixed hex; require the exact GP extent and complete pairs before byte decoding.
  if text.len != ParameterBytes * 2: return ParameterResult(success: false, reason: wrongSize)
  var bytes = default(array[ParameterBytes, byte])
  for i in 0..<text.len: # Each nibble is validated before narrowing into the fixed destination.
    let c = text[i]
    var nibble = 0
    if c in {'0'..'9'}: nibble = ord(c) - ord('0')
    elif c in {'a'..'f'}: nibble = ord(c) - ord('a') + 10
    elif c in {'A'..'F'}: nibble = ord(c) - ord('A') + 10
    else: return ParameterResult(success: false, reason: invalidConfiguration)
    bytes[i div 2] = byte(int(bytes[i div 2]) * 16 + nibble)
  decodeParameters(bytes)
