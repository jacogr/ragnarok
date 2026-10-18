# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP v0.8.0 guarantorsig composition; callers validate and serialize complete report bytes.
##
## Exposes guaranteeMessage and its owned signing-transcript/result types.

import ./primitives

type
  # The normative domain plus report hash is distinct from a signature or raw digest.
  GuaranteeMessage* = distinct array[45, byte]

  # This composition owns its checked result; primitive constructors remain private to their module.
  GuaranteeMessageResult* = object
    case status: CryptoError
    of None:
      # Only a completed hash/domain construction carries signing bytes.
      completed: GuaranteeMessage
    else:
      # Defaults and backend refusals carry no partial or zero message.
      discard

# Preserve primitive failure reasons through a read-only composition outcome.
func error*(value: GuaranteeMessageResult): CryptoError = value.status

# A fixed message copy is available only after successful domain/hash construction.
func value*(value: GuaranteeMessageResult): GuaranteeMessage {.inline, requires: value.status ==
    CryptoError.None.} =
  value.completed

# Hash exact canonical report bytes and prepend ASCII jam_guarantee, without a timeslot or second hash.
# This function does not establish validator assignments or resolve the Ed25519 acceptance-policy gate.
proc guaranteeMessage*(canonicalReport: openArray[byte]): GuaranteeMessageResult {.raises: [].} =
  let hashed = blake2b256(canonicalReport)
  # Failed provider calls expose no partial or all-zero signing message.
  if hashed.error != CryptoError.None: return GuaranteeMessageResult(status: hashed.error)
  var message = default(array[45, byte])
  const domain = "jam_guarantee"
  # Copy the ASCII token bytes without a dollar sign or string terminator.
  for i in 0..<domain.len: message[i] = byte(domain[i])
  let bytes = array[32, byte](hashed.value)
  # Hash identity bytes follow the domain in their original order.
  for i in 0..<32: message[13+i] = bytes[i]
  GuaranteeMessageResult(status: CryptoError.None, completed: GuaranteeMessage(message))
