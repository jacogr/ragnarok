# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine deterministic Ed25519 credentials for original computed messages and owner-selected test keys.

import std/assertions
import ../../src/state/[computed_guarantors, computed_roster, computed_transition, computed_profile,
  computed_lookup, computed_recent, computed_state, computed_links, computed_guarantee]
import ../../src/codec/[guarantees, state_safrole]
import ../../src/crypto/[primitives, guarantee]
import ./pvm_computed_guarantors

proc credentialFixture*(shrink = false, core = 0'u64, offender = false,
    target = 0'u32): ComputedGuarantors =
  ## Run real original computation and authenticated posterior planning before any credential signing.
  let source = guarantorFixture(shrink = shrink, core = core, offender = offender, target = target)
  prepareComputedGuarantors(source, guarantorLimits()).value
proc credentialMessage*(source: ComputedGuarantors): array[45, byte] =
  ## Copy exact retained original message for test signing; production verification accepts no caller message.
  let transcript = source.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value.computedStateSource.value.computedLinkSource.value
  array[45, byte](transcript.computedGuaranteeMessage.value)
proc credentialSignature*(seedByte: byte, message: openArray[byte]): GuaranteeSignature =
  ## Real deterministic ordinary Ed25519 signs only explicitly supplied test messages.
  var bytes = default(array[32, byte])
  bytes[0] = seedByte
  let seed = importSeed(bytes).value
  GuaranteeSignature(array[64, byte](sign(seed, message).value))
proc signedCredentials*(source: ComputedGuarantors, slot: GuaranteeSlot,
    indices: openArray[uint16], message: openArray[byte]): seq[GuaranteeCredential] =
  ## Match known authored test seed identities to each genuinely selected roster key; preserve caller order for hostile tests.
  result = newSeq[GuaranteeCredential](indices.len)
  for i, index in indices:
    let selected = source.computedGuarantorAt(slot, GuarantorIndex(index))
    assert selected.error == ComputedGuarantorError.None, "genuine eligible test signer"
    var matched = false
    for number in 11..19:
      var bytes = default(array[32, byte])
      bytes[0] = byte(number)
      let seed = importSeed(bytes).value
      if array[32, byte](publicKey(seed).value) == array[32, byte](
          selected.value.validator.ed25519):
        result[i] = GuaranteeCredential(validator: GuarantorIndex(index),
          signature: GuaranteeSignature(array[64, byte](sign(seed, message).value)))
        matched = true
        break # Exactly the first matching authored private test seed signs; no production verification is replaced.
    assert matched, "selected key must have a real authored test seed"
