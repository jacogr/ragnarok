## Focused lifetime, immutable-copy, atomicity, alias and runtime result-guard tests.
import ../../src/codec/bitstrings

# Only a selected complete success can supply native metadata, owners or written extents.
proc checked[T](parsed: BitResult[T]): T =
  doAssert parsed.error == BitError.None
  parsed.value

let limit = BitLimit(1024)
var input = @[9'u8, 0x81, 1, 0x99]
var owner = checked(decodeBits(input, limit)).owner
var retained = owner
owner = OwnedBits()
# All retained bits must outlive and ignore the caller's original mutable input.
for i in 0..<input.len: input[i] = 0
let info = checked(bitsInfo(retained))
doAssert uint64(info.count) == 9 and info.packedBytes == 2
doAssert checked(bitAt(retained, 0)) and checked(bitAt(retained, 7)) and checked(bitAt(retained, 8))
doAssert not checked(bitAt(retained, 1))
doAssert bitAt(retained, -1).error == BitError.InvalidIndex
doAssert bitAt(retained, 9).error == BitError.InvalidIndex
var output: array[16, byte]
# Fixed and variable framing preserve all destination suffix capacity.
for i in 0..<output.len: output[i] = 0xA5
doAssert checked(encodeOwnedBits(retained, limit, output)) == 3
doAssert output[0..2] == @[9'u8, 0x81, 1]
doAssert output[3] == 0xA5
output[1] = 0
# Mutating extracted bytes can never mutate the private immutable snapshot.
doAssert checked(bitAt(retained, 0))
doAssert checked(encodeOwnedFixedBits(retained, BitCount(9), limit, output)) == 2
doAssert output[0..1] == @[0x81'u8, 1]
# A stricter caller policy must be applied again to retained snapshots before any output writes.
for i in 0..<output.len: output[i] = 0xA5
doAssert encodeOwnedBits(retained, BitLimit(8), output).error == BitError.LimitExceeded
doAssert encodeOwnedFixedBits(retained, BitCount(8), limit, output).error == BitError.InvalidCount
var empty: seq[byte]
doAssert encodeOwnedBits(retained, limit, empty).error == BitError.OutputTooSmall
# All failed source-policy and capacity checks leave the complete output unchanged.
for octet in output: doAssert octet == 0xA5
var missing: OwnedBits
doAssert bitsInfo(missing).error == BitError.InvalidOwner
doAssert bitAt(missing, 0).error == BitError.InvalidOwner
doAssert encodeOwnedBits(missing, limit, output).error == BitError.InvalidOwner
doAssert encodeOwnedFixedBits(missing, BitCount(0), limit, output).error == BitError.InvalidOwner
let zero = checked(decodeFixedBits(empty, BitCount(0), BitLimit(0))).owner
doAssert uint64(checked(bitsInfo(zero)).count) == 0
doAssert checked(encodeOwnedFixedBits(zero, BitCount(0), BitLimit(0), empty)) == 0
doAssert checked(encodeOwnedBits(zero, BitLimit(0), output)) == 1 and output[0] == 0
# A copied owner is independent of subsequent destruction of other handles.
retained = OwnedBits()
doAssert bitAt(zero, 0).error == BitError.InvalidIndex
# Borrowed bool storage cannot overlap any part of the written frame, even its earlier count prefix.
var backing: array[32, bool]
let storage = cast[ptr UncheckedArray[byte]](addr backing[0])
doAssert sizeof(bool) == 1
let aliasResult = encodeBits(backing.toOpenArray(1, 9), limit, storage.toOpenArray(0, 2))
doAssert aliasResult.error == BitError.AliasedBuffers
# Failed alias preflight must leave the bool representations valid and unchanged.
for value in backing: doAssert not value
doAssert encodeFixedBits(backing.toOpenArray(1, 9), BitCount(9), limit,
  storage.toOpenArray(0, 1)).error == BitError.AliasedBuffers
# Source cardinality and policy precede output capacity, even for an empty destination.
doAssert encodeFixedBits(backing, BitCount(31), BitLimit(0), empty).error == BitError.InvalidCount
doAssert encodeBits(backing, BitLimit(0), empty).error == BitError.LimitExceeded
# Successful snapshotting permits the original caller input to become an output destination later.
input = @[9'u8, 0x81, 1]
let independent = checked(decodeBits(input, limit)).owner
doAssert checked(encodeOwnedBits(independent, limit, input)) == 3
var guarded = false
try:
  # A rejected Boolean must not be observable as a default false or successful consumption.
  discard decodeBoolean(@[2'u8]).value.value
except FieldDefect:
  # The checked optimized build must preserve Nim's selected-alternative guard.
  guarded = true
doAssert guarded
guarded = false
try:
  # A default generic result likewise cannot expose a fabricated empty owner.
  var absent: BitResult[BitsRead]
  discard absent.value.consumed
except FieldDefect:
  # This protects uninitialized results independently of decoder failure cases.
  guarded = true
doAssert guarded
echo "Nim bits: retained ownership, atomicity, aliases and selected-result guards passed"
