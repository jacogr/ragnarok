## Native success/default tests complement independent field/byte, fuzz and overlap comparisons.
import std/[assertions, syncio]
import ../../../src/codec/assurances

let config = AssuranceConfig(cores: CoreCount(2), validators: ValidatorCount(6))
let missingWrite = default(AssuranceWriteResult)
let missingDecode = default(AssuranceDecodeResult)
assert missingWrite.error == AssuranceError.Uninitialized
assert missingDecode.error == AssuranceError.Uninitialized
assert validConfig(config)
assert not validConfig(AssuranceConfig(cores: CoreCount(high(uint64)), validators: ValidatorCount(6)))
assert not validConfig(AssuranceConfig(cores: CoreCount(2), validators: ValidatorCount(high(uint64))))
let none: seq[Assurance] = @[]
var emptyWire = [byte(77), 77]
let encodedEmpty = encodeAssurances(none, config, emptyWire)
assert encodedEmpty.error == AssuranceError.None and encodedEmpty.written == 1
assert emptyWire == [byte(0), 77]
var output = default(array[2, Assurance])
let emptyDecoded = decodeAssurances(emptyWire, config, output)
let emptyScanned = inspectAssurances(emptyWire, config)
assert emptyDecoded.error == AssuranceError.None and emptyDecoded.count == 0 and
    emptyDecoded.consumed == 1
assert emptyScanned.error == AssuranceError.None and emptyScanned.count == 0 and
    emptyScanned.consumed == 1

# Return copied fixed-field records after their complete source storage has gone out of scope.
proc escaped(): Assurance =
  var source = default(array[1, Assurance])
  source[0].anchor.bytes[0] = 11
  source[0].bits.bytes[0] = 3
  source[0].validator = ValidatorIndex(5)
  source[0].signature.bytes[63] = 22
  var wire = default(array[103, byte])
  let encoded = encodeAssurances(source, config, wire)
  assert encoded.error == AssuranceError.None and encoded.written == 100
  var copied = default(array[1, Assurance])
  let decoded = decodeAssurances(wire, config, copied)
  assert decoded.error == AssuranceError.None and decoded.count == 1 and decoded.consumed == 100
  let scanned = inspectAssurances(wire, config)
  assert scanned.error == AssuranceError.None and scanned.count == 1 and scanned.consumed == 100
  # Alter both original typed values and wire bytes; neither may affect the decoded owned value.
  source[0].anchor.bytes[0] = 99
  wire[1] = 99
  copied[0]

let retained = escaped()
assert retained.anchor.bytes[0] == 11 and retained.bits.bytes[0] == 3
assert uint16(retained.validator) == 5 and retained.signature.bytes[63] == 22
# Reading record padding verifies explicit zero initialization after a tiny-profile decode.
for i in 1..<43: assert retained.bits.bytes[i] == 0
var detached = retained
# Modifying a copied fixed record must not change its retained predecessor.
detached.anchor.bytes[0] = 99
assert retained.anchor.bytes[0] == 11
assert detached.anchor.bytes[0] == 99
echo "Assurances: guarded defaults, empty prefixes, escaped records, copied metadata and padding passed"
