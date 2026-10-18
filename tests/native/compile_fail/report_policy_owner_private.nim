## Policy certificates and result internals remain private across application boundaries.
import ../../../src/state/report_policy
let owner = default(PolicyCheckedReports)
discard owner.data # Must fail before lowering.
