## Callers may inspect only the read-only error accessor.
import ../../../src/crypto/assurance_context
let parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
discard parsed.status
