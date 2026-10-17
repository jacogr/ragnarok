## Result storage stays private; failed/default snapshots cannot be exposed or retagged.
import ../../../src/state/validator_state
var hidden = default(ValidatorStateResult)
hidden.status = ValidatorStateError.None
