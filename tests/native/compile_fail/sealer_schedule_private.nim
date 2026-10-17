## Candidate storage remains private on every default, failed and successful schedule result.
import ../../../src/state/sealer_schedule
var hidden = default(SealerScheduleResult)
discard hidden.completed
