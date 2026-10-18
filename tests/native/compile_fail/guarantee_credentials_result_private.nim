## External callers cannot access private credential certification storage.
import ../../../src/state/guarantee_credentials
let owner = default(GuaranteeCredentialResult[VerifiedGuaranteeCredentials])
discard owner.completed # Must fail before native lowering.
