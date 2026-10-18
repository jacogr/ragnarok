## External callers cannot forge assignment candidates or retag failed planning results.
import ../../../src/state/report_assignments
let owner = default(ReportAssignmentPlan)
discard owner.data # Must fail before lowering.
