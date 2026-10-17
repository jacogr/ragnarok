import ../../support/arc_evidence
## Guarantee transcript fixed copies, exact known answers and observer-only backend refusal/recovery.
import std/[assertions, syncio]
import ../../native/batch_support
import ../../../src/crypto/[primitives, guarantee]

# Refusal is isolated to this test observer, while successful hashes use the production bridge.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Copied counts prove one exact hash per attempted transcript, including empty raw input.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Decode the independent hashlib-known answer into fixed expected storage without a production codec.
proc known(hex: string): array[46, byte] =
  assert hex.len == 92
  result = default(array[46, byte])
  # Every expected byte includes the leading dollar sign and the full parameterized 32-byte digest.
  for i in 0..<46: result[i] = octet(hex[2*i..2*i+1])

# One scope owns only copied transcript values; no borrow may survive into the completed result.
proc exercise() =
  fail(0)
  let empty = guaranteeMessage([])
  assert empty.error == CryptoError.None
  assert array[46, byte](empty.value) == known("246a616d5f67756172616e7465650e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8")
  assert hashCalls() == 1
  var source = [1'u8, 2, 3]
  let message = guaranteeMessage(source)
  assert message.error == CryptoError.None and source == [1'u8, 2, 3]
  let saved = array[46, byte](message.value)
  source[0] = 99
  var copied = array[46, byte](message.value)
  copied[0] = 0
  assert array[46, byte](message.value) == saved # Neither source nor extracted-copy mutation changes the completed message.
  assert saved == known("246a616d5f67756172616e74656511c0e79b71c3976ccd0c02d1310e2516c08edc9d8b6f57ccd680d63a4d8e72da")
  fail(1)
  assert guaranteeMessage(source).error == CryptoError.BackendFailure
  assert hashCalls() == 1 and source == [99'u8, 2,
      3] # Failure neither publishes bytes nor mutates borrowed input.
  assert guaranteeMessage([]).error == CryptoError.BackendFailure
  assert hashCalls() == 2
  fail(0)
  source[0] = 1
  assert array[46, byte](guaranteeMessage(source).value) == saved
  assert hashCalls() == 1

exercise()
# Warmup isolates allocator initialization from this fixed-message workload.
for i in 0..<20: exercise()
let beforeRelease = getOccupiedMem()
# Fixed outputs and synchronous hashing must leave no new live Nim storage after each scope.
for i in 0..<1000: exercise()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("guarantee_message", 1000, beforeRelease, afterRelease)
echo "GUARANTEE_MESSAGE_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony guarantee message: known answers, fixed copies, refusal/recovery and scoped release passed"
