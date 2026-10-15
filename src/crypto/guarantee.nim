## GP v0.8.0 guarantorsig composition; callers validate and serialize complete report bytes.
import ./primitives

type
  # The normative domain plus report hash is distinct from a signature or raw digest.
  GuaranteeMessage* = distinct array[46, byte]

# Hash exact canonical report bytes and prepend ASCII $jam_guarantee, without a timeslot or second hash.
# This function does not establish validator assignments or resolve the Ed25519 acceptance-policy gate.
proc guaranteeMessage*(canonicalReport: openArray[byte]): CryptoResult[GuaranteeMessage] {.raises: [].} =
  let hashed = blake2b256(canonicalReport)
  # Failed provider calls expose no partial or all-zero signing message.
  if hashed.error != CryptoError.None: return CryptoResult[GuaranteeMessage](error: hashed.error)
  var message: array[46, byte]
  const domain = "$jam_guarantee"
  # Copy the literal domain including its leading dollar sign, without a string terminator.
  for i in 0..<domain.len: message[i] = byte(domain[i])
  let bytes = array[32, byte](hashed.value)
  # Hash identity bytes follow the domain in their original order.
  for i in 0..<32: message[14+i] = bytes[i]
  CryptoResult[GuaranteeMessage](error: CryptoError.None, value: GuaranteeMessage(message))
