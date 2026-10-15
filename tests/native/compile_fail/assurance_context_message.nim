## Intentional wrong-domain assignment must be rejected before runtime.
import ../../../src/crypto/[primitives, assurance_context]
import ../../../src/assurances
let value: EdSignature = default(AssuranceSigningMessage)
discard value
