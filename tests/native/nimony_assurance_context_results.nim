## Isolated actual/default assurance transcript and verified-count reads require supported success contracts.
import std/[assertions, cmdline, strutils, syncio]
import ../../src/crypto/[primitives, assurance_context]
import ../../src/codec/assurances

# Sequential fault injection applies only to the test observer library.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}

let mode = paramStr(1)
let useDefault = paramStr(2) == "default"
let parent = default(AssuranceParent)
var bits = default(AssuranceBits)
fail(0)
if mode.startsWith("message-"):
  var cores = CoreCount(2)
  var wanted = AssuranceContextError.NonCanonical
  case mode
  of "message-config":
    cores = CoreCount(high(uint64)) # Reject width calculation before hashing or indexing.
    wanted = AssuranceContextError.InvalidConfig
  of "message-padding": bits.bytes[42] = 1 # Invalid unused native storage cannot be signed.
  of "message-backend":
    fail(1) # No failed digest can become a usable zero signing transcript.
    wanted = AssuranceContextError.BackendFailure
  else: quit 2 # Unknown modes cannot count as a successful guard check.
  let parsed = if useDefault: default(AssuranceContextResult[
      AssuranceSigningMessage]) else: assuranceMessage(parent, bits, cores)
  assert parsed.error == (if useDefault: AssuranceContextError.Uninitialized else: wanted)
  echo array[46, byte](parsed.value)[0]
else:
  var config = AssuranceConfig(cores: CoreCount(2), validators: ValidatorCount(6))
  let seed = importSeed(default(array[32, byte])).value
  let key = publicKey(seed).value
  var keys = newSeq[EdPublicKey](6)
  # A nonexceptional derived key isolates ordinary invalid-signature behavior from point-policy questions.
  for i in 0..<keys.len: keys[i] = key
  var values = newSeq[Assurance](1)
  var wanted = AssuranceContextError.NonCanonical
  case mode
  of "verify-config":
    config.cores = CoreCount(high(uint64)) # Configuration failure precedes all batch work.
    wanted = AssuranceContextError.InvalidConfig
  of "verify-keys":
    keys.setLen(5) # Incomplete key mappings cannot authorize an empty or nonempty batch.
    wanted = AssuranceContextError.InvalidKeySet
  of "verify-count":
    values.setLen(7) # Count policy precedes duplicate/index validation.
    wanted = AssuranceContextError.LimitExceeded
  of "verify-index":
    values[0].validator = ValidatorIndex(6) # Fixed index storage still needs configured membership.
    wanted = AssuranceContextError.InvalidValidator
  of "verify-order": values.setLen(2) # Two zero validator identities violate strict order.
  of "verify-padding": values[0].bits.bytes[42] = 1 # Unused native octets are not ignored.
  of "verify-parent":
    values[0].anchor.bytes[0] = 1 # Expected parent is an external context requirement.
    wanted = AssuranceContextError.WrongParent
  of "verify-backend":
    fail(1) # A refusal cannot expose an earlier verified prefix count.
    wanted = AssuranceContextError.BackendFailure
  of "verify-signature": wanted = AssuranceContextError.InvalidSignature # Zero signature against an ordinary key rejects.
  else: quit 2 # Unknown fixture operations are setup errors.
  let parsed = if useDefault: default(AssuranceContextResult[
      VerifiedAssuranceCount]) else: verifyAssurances(values, config, parent, keys)
  assert parsed.error == (if useDefault: AssuranceContextError.Uninitialized else: wanted)
  clearSeed(seed)
  echo uint64(parsed.value)
