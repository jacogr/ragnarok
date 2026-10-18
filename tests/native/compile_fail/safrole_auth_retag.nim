## Authentication result state/payload remain private across default, failed and successful outcomes.
import ../../../src/state/safrole_authentication
var hidden = default(SafroleAuthResult)
hidden.status = SafroleAuthError.None
