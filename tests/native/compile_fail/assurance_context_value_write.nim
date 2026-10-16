## The public success accessor does not expose mutable result storage.
import ../../../src/crypto/assurance_context
var parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
parsed.value = VerifiedAssuranceCount(1)
