## Callers cannot manufacture successful selection by changing the private result discriminator.
import ../../../src/state/sealer_schedule
var hidden = default(SealerScheduleResult)
hidden.status = SealerScheduleError.None
