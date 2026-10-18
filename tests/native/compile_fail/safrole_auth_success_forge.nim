## Statically known success is forbidden by the failure-only authentication result factory.
import ../../../src/state/safrole_authentication
discard safroleAuthFailure(SafroleAuthError.None)
