## External callers cannot access private credential certification storage.
import ../../../src/state/guarantee_credentials
let owner = default(VerifiedGuaranteeCredentials)
discard owner.data # Must fail before native lowering.
