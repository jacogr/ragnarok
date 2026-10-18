## Policy certificates and result internals remain private across application boundaries.
import ../../../src/state/report_policy
let owner = default(ReportPolicyResult[PolicyCheckedReports])
discard owner.completed # Must fail before lowering.
