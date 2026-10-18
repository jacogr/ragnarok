## Policy certificates and result internals remain private across application boundaries.
import ../../../src/state/report_policy
let owner = default(ReportPolicyResult[PolicyCheckedReports])
discard owner.status # Must fail before lowering.
