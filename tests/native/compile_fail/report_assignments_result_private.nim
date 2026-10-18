## External callers cannot forge assignment candidates or retag failed planning results.
import ../../../src/state/report_assignments
let owner = default(ReportAssignmentResult[ReportAssignmentPlan])
discard owner.completed # Must fail before lowering.
