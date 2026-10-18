# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JIP-3 v1 registration and event encoding; pinned layout and limits: spec/telemetry.md.
## Values own their bytes; encoding never retains borrowed input or native pointers.
import ../codec/natural

const MetadataSize* = 204
const MaxCores* = 1024

# Wire assignments from the pinned JIP-3 revision linked in spec/telemetry.md.
# The registration version is separate from the event discriminator namespace.
const ProtocolVersion = 1'u8 # JIP-3 "Node information": telemetry protocol version.
const DroppedEvent = 0'u8 # JIP-3 event 0: a contiguous run of omitted observations.
const StatusEvent = 10'u8 # JIP-3 event 10: current peer counts and pool sizes.
const ConnectionRefusedEvent = 20'u8 # JIP-3 event 20: an incoming connection is explicitly refused.
const ConnectingInEvent = 21'u8 # JIP-3 event 21: an incoming handshake starts.
const ConnectInFailedEvent = 22'u8 # JIP-3 event 22: that incoming handshake fails.
const ConnectedInEvent = 23'u8 # JIP-3 event 23: that incoming handshake succeeds.
const ConnectingOutEvent = 24'u8 # JIP-3 event 24: an outgoing connection attempt starts.
const ConnectOutFailedEvent = 25'u8 # JIP-3 event 25: that outgoing attempt fails.
const ConnectedOutEvent = 26'u8 # JIP-3 event 26: that outgoing attempt succeeds.
const DisconnectedEvent = 27'u8 # JIP-3 event 27: an authenticated peer connection closes.
const UnknownConnectionSide = 0'u8 # JIP-3 Option<Connection Side>: absent terminator attribution.

type
  # Microseconds since the JAM Common Era, deliberately distinct from Unix time.
  Timestamp* = distinct uint64
  # Implicit position in the telemetry event stream, preserved across collector reconnects.
  EventId* = distinct uint64
  # Operator-supplied network parameters, genesis, identity and advertised address.
  Metadata* = object
    bytes: array[MetadataSize, byte]
    cores: uint16
  # Invalid metadata carries only a reason, never a usable registration snapshot.
  MetadataError* = enum
    wrongSize, invalidCoreCount, invalidChain, hashFailed
  MetadataResult* = object
    case success: bool
    of true:
      snapshot: Metadata
    of false:
      reason: MetadataError

# Discriminators are read-only; callers must establish success before extraction.
func ok*(value: MetadataResult): bool = value.success
# Copy an immutable fixed-sized snapshot only after successful validation.
func value*(value: MetadataResult): Metadata {.requires: value.success.} = value.snapshot
# Explain rejection without exposing default metadata as a success.
func error*(value: MetadataResult): MetadataError {.requires: not value.success.} = value.reason
# Return the validated number of cores needed for the fixed-size guarantee array.
func coreCount*(value: Metadata): uint16 = value.cores

# Validate before copying; parameters are externally supplied, never inferred from a test profile.
proc metadata*(input: openArray[byte]): MetadataResult =
  # The pinned fetch-parameter layout plus genesis/identity/address has an exact extent.
  if input.len != MetadataSize: return MetadataResult(success: false, reason: wrongSize)
  let cores = uint16(input[24]) or (uint16(input[25]) shl 8)
  # Bound every later allocation, rejecting nonsensical or unsupported network sizes.
  if cores == 0 or cores > uint16(MaxCores):
    return MetadataResult(success: false, reason: invalidCoreCount)
  var snapshot = Metadata(cores: cores)
  # Copy only after the entire input shape has been established.
  for i in 0..<MetadataSize: snapshot.bytes[i] = input[i]
  MetadataResult(success: true, snapshot: snapshot)

# Append a fixed-width little-endian integer; callers use protocol-defined widths only.
proc fixed(output: var seq[byte], value: uint64, width: range[1..8]) =
  # Mask before narrowing so checked builds cannot truncate an unchecked value.
  for i in 0..<width: output.add(byte((value shr (8 * i)) and 255))

# Encode constant ASCII metadata with the existing canonical JAM natural codec.
proc text(output: var seq[byte], value: string) =
  let length = encode(JamNatural(uint64(value.len)))
  # Only the natural's initialized prefix belongs on the wire.
  for i in 0..<length.len: output.add(length.bytes[i])
  # All implementation-owned strings below are ASCII, hence valid UTF-8.
  for character in value: output.add(byte(character))

# Finish the reserved E4 prefix; internal producers are bounded to fewer than 2048 bytes.
proc frame(output: var seq[byte]) =
  let size = uint32(output.len - 4)
  # Prefix length excludes its own four bytes, including on the registration message.
  for i in 0..<4: output[i] = byte((size shr (8 * i)) and 255)

# Produce a complete registration frame; zero flags and note explicitly describe the proof peer.
proc registration*(value: Metadata): seq[byte] {.requires: value.cores > 0.} =
  result = @[0'u8, 0, 0, 0, ProtocolVersion]
  # Parameters, genesis, identity and IPv6/port bytes are already in their pinned wire order.
  for item in value.bytes: result.add(item)
  result.fixed(0, 4)
  result.text("Ragnarok")
  result.text("development")
  result.text("0.8.0")
  result.text("Proof peer; no PVM, chain execution or validator operation")
  result.frame()

# Report currently connected peers and empty unimplemented pools; no chain/sync claims are emitted.
proc status*(value: Metadata, timestamp: Timestamp, peers: uint32): seq[
    byte] {.requires: value.cores > 0.} =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(StatusEvent)
  result.fixed(peers, 4)
  result.fixed(0, 4) # No validator-role classification exists in the proof peer.
  result.fixed(0, 4) # No block-announcement streams are implemented.
  # The per-core array is fixed-width, with no sequence-length prefix.
  for i in 0..<int(value.cores): result.add(0)
  result.fixed(0, 4) # No availability shards are stored.
  result.fixed(0, 8)
  result.fixed(0, 4) # CE fixture responses are not a block-production preimage pool.
  result.fixed(0, 4)
  result.frame()

# Replace contiguous unsent event observations with the normative two-timestamp dropped event.
proc dropped*(first, last: Timestamp, count: uint64): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(first), 8)
  result.add(DroppedEvent)
  result.fixed(uint64(last), 8)
  result.fixed(count, 8)
  result.frame()

# Publish a typed configuration failure without exposing partially parsed metadata.
func invalidMetadata*(reason: MetadataError): MetadataResult =
  MetadataResult(success: false, reason: reason)

# Record a real outgoing dial using its pinned identity and copied IPv6-format destination.
proc connectingOut*(timestamp: Timestamp, identity: array[32, byte], address: array[16, byte],
    port: uint16): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(ConnectingOutEvent)
  # Both fields have fixed protocol extents and no length prefixes.
  for item in identity: result.add(item)
  for item in address: result.add(item)
  result.fixed(port, 2)
  result.frame()

# Link authentication success to the original attempt, never to a status observation.
proc connectedOut*(timestamp: Timestamp, attempt: EventId): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(ConnectedOutEvent)
  result.fixed(uint64(attempt), 8)
  result.frame()

# Link failure to its attempt; an empty normative Reason avoids inventing a native TLS diagnosis.
proc connectOutFailed*(timestamp: Timestamp, attempt: EventId): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(ConnectOutFailedEvent)
  result.fixed(uint64(attempt), 8)
  result.text("")
  result.frame()

# Record an observed authenticated connection close without guessing its initiator or native reason.
proc disconnected*(timestamp: Timestamp, identity: array[32, byte]): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(DisconnectedEvent)
  # The public peer identity is fixed-width and copied into the returned frame.
  for item in identity: result.add(item)
  result.add(UnknownConnectionSide)
  result.text("") # The transport does not expose a reliable diagnostic for this close.
  result.frame()

# Capture the incoming remote address before TLS authentication completes.
proc connectingIn*(timestamp: Timestamp, address: array[16, byte], port: uint16): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(ConnectingInEvent)
  for item in address: result.add(item) # Fixed IPv6-format address has no length prefix.
  result.fixed(port, 2)
  result.frame()

# Link an authenticated incoming identity to its pre-handshake observation.
proc connectedIn*(timestamp: Timestamp, attempt: EventId, identity: array[32, byte]): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(ConnectedInEvent)
  result.fixed(uint64(attempt), 8)
  for item in identity: result.add(item) # Public identity is copied only after native authentication.
  result.frame()

# Settle an unfinished incoming handshake without inventing a diagnostic string.
proc connectInFailed*(timestamp: Timestamp, attempt: EventId): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(ConnectInFailedEvent)
  result.fixed(uint64(attempt), 8)
  result.text("")
  result.frame()

# Report an explicit admission refusal with only its copied remote endpoint, as required by JIP-3.
proc connectionRefused*(timestamp: Timestamp, address: array[16, byte], port: uint16): seq[byte] =
  result = @[0'u8, 0, 0, 0]
  result.fixed(uint64(timestamp), 8)
  result.add(ConnectionRefusedEvent)
  for item in address: result.add(item) # Fixed IPv6-format bytes, without a length prefix.
  result.fixed(port, 2)
  result.frame()
