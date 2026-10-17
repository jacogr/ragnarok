## Callers cannot manufacture successful selection by changing the private result discriminator.
import ../../../src/state/[sealer_state, sealer_schedule]
var hidden = default(SealerStateResult)
hidden.status = SealerScheduleError.None
