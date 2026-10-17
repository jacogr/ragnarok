## Candidate storage remains private on every default, failed and successful schedule result.
import ../../../src/state/sealer_state
var hidden = default(SealerStateResult)
discard hidden.completed
