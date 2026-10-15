import ../../../src/[guarantees, assurances]
# Assurance and guarantor identities require deliberate domain conversion.
let wrong = GuaranteeCredential(validator: ValidatorIndex(1))
discard wrong
