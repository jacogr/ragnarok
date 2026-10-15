import ../../../src/[guarantees, assurances]
# Assurance signature bytes cannot occupy a guarantee credential implicitly.
let wrong = GuaranteeCredential(signature: AssuranceSignature())
discard wrong
