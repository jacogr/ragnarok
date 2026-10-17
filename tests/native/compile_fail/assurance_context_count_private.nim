## Count storage must remain private even on a default result.
import ../../../src/crypto/assurance_context
let parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
discard parsed.completed
