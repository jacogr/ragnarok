## Callers cannot retag failed/default results as success.
import ../../../src/crypto/assurance_context
var parsed = default(AssuranceContextResult[VerifiedAssuranceCount])
parsed.status = AssuranceContextError.None
