# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded operator-supplied network identity: opaque fetch bytes and the complete serialized
## genesis-header hash. This projection does not validate a state snapshot or grant consensus authority.
import std/[parsejson, streams, strutils, parseutils]
import ../crypto/primitives
import ./genesis

const
  MaxNetworkChainBytes* = 8 * 1024 * 1024 ## Bound complete JSON before event-parser allocation.
  MaxNetworkHeaderBytes* = 256 * 1024     ## Accommodate full validator epoch markers under a finite policy.

type
  NetworkIdentityError* {.pure.} = enum ## Default or failed parsing publishes no partial domain.
    Uninitialized, None, InvalidChain, HashFailed
  NetworkIdentity* = object ## Fixed copied configuration bytes never retain parser or state-map storage.
    initialized: bool
    encoded: array[122, byte]
    genesis: BlockHash
  NetworkIdentityResult* = object ## Only successful parsing permits snapshot extraction.
    case status: NetworkIdentityError
    of None: completed: NetworkIdentity
    else: discard                 # Invalid/default results contain reasons only.

func error*(outcome: NetworkIdentityResult): NetworkIdentityError =
  ## Inspect parsing failure without accessing any partially initialized identity.
  outcome.status
func value*(outcome: NetworkIdentityResult): NetworkIdentity {.requires: outcome.status ==
    NetworkIdentityError.None.} =
  ## Copy only a complete fixed network identity.
  outcome.completed
func ready*(identity: NetworkIdentity): bool =
  ## A default fixed value cannot publish an operator-selected network identity.
  identity.initialized
func parametersBytes*(identity: NetworkIdentity): array[122,
    byte] {.requires: identity.initialized.} =
  ## Fetch bytes remain uninterpreted; consumers validate their own parameter or telemetry geometry.
  identity.encoded
func genesisHash*(identity: NetworkIdentity): BlockHash {.requires: identity.initialized.} =
  ## This is the configured original header, never a best-head or state-root replacement.
  identity.genesis

proc hexBytes(text: string, maximum: int): seq[byte] =
  ## Decode an exact bounded hex field atomically; empty output means invalid, never a valid field here.
  result = @[]
  # Both supported fields must be nonempty and have a complete pair per byte.
  if text.len == 0 or text.len mod 2 != 0 or text.len div 2 > maximum: return
  var bytes = newSeq[byte](text.len div 2)
  # Validate every pair before publishing the newly owned sequence.
  for i in 0..<bytes.len:
    let start = 2 * i
    if text[start] notin HexDigits or text[start + 1] notin HexDigits:
      return # parseHex also accepts prefixes and underscores; JIP-4 fields permit only digit pairs.
    var value = 0'u8
    if parseHex(text, value, start, 2) != 2: return # Require the complete pair before publishing any bytes.
    bytes[i] = value # Two validated digits fit exactly in a byte; no overflow or truncation is possible.
  result = move(bytes)

proc readNetworkIdentity*(text: string): NetworkIdentityResult =
  ## Parse complete bounded JSON and hash its serialized genesis header using the maintained primitive.
  # Limit input before the standard token parser creates any strings or parser states.
  if text.len == 0 or text.len > MaxNetworkChainBytes: return NetworkIdentityResult(
      status: NetworkIdentityError.InvalidChain)
  var parser = default(JsonParser)
  parser.open(newStringStream(text), "telemetry chain")
  defer: parser.close() # Parser-owned stream and token storage have no escaping borrows.
  parser.next()
  if parser.kind != jsonObjectStart: return NetworkIdentityResult(
      status: NetworkIdentityError.InvalidChain)
  var depth = 1
  var wantKey = true
  var key = ""
  var parameters, header = ""
  var hasParameters, hasHeader = false
  # The standard event parser validates punctuation; depth bounds its iterative state stack.
  while depth > 0:
    parser.next()
    let kind = parser.kind
    if kind in [jsonError, jsonEof]: return NetworkIdentityResult(
        status: NetworkIdentityError.InvalidChain)
    if depth == 1 and kind != jsonObjectEnd:
      if wantKey:
        # Top-level object members require string keys before any value is inspected.
        if kind != jsonString: return NetworkIdentityResult(
            status: NetworkIdentityError.InvalidChain)
        key = parser.str
        wantKey = false
      else:
        # Only these two JIP-4 fields feed telemetry; duplicate relevant keys are ambiguous.
        if key == "protocol_parameters":
          if kind != jsonString or hasParameters: return NetworkIdentityResult(
              status: NetworkIdentityError.InvalidChain)
          parameters = parser.str
          hasParameters = true
        elif key == "genesis_header":
          if kind != jsonString or hasHeader: return NetworkIdentityResult(
              status: NetworkIdentityError.InvalidChain)
          header = parser.str
          hasHeader = true
        wantKey = true
    if kind in [jsonObjectStart, jsonArrayStart]:
      inc depth
      if depth > 32: return NetworkIdentityResult(
          status: NetworkIdentityError.InvalidChain) # Bound nested unused state/extension data too.
    elif kind in [jsonObjectEnd, jsonArrayEnd]:
      dec depth # Standard parser enforces matching delimiters.
  parser.next()
  if parser.kind != jsonEof or not hasParameters or not hasHeader: return NetworkIdentityResult(
      status: NetworkIdentityError.InvalidChain)
  let params = hexBytes(parameters, 122)
  let genesis = hexBytes(header, MaxNetworkHeaderBytes)
  if params.len != 122 or genesis.len == 0: return NetworkIdentityResult(
      status: NetworkIdentityError.InvalidChain)
  let digest = blake2b256(genesis)
  if digest.error != CryptoError.None: return NetworkIdentityResult(
      status: NetworkIdentityError.HashFailed)
  var encoded = default(array[122, byte])
  for index in 0..<122: encoded[index] = params[index] # Exact width was checked before any fixed-array access.
  NetworkIdentityResult(status: NetworkIdentityError.None,
    completed: NetworkIdentity(initialized: true, encoded: encoded, genesis: BlockHash(array[32,
        byte](digest.value))))
