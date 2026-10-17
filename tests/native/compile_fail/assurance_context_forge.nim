## Callers cannot manufacture a verified credential count.
import ../../../src/crypto/assurance_context
discard AssuranceContextResult[VerifiedAssuranceCount](status: AssuranceContextError.None,
    completed: VerifiedAssuranceCount(1))
