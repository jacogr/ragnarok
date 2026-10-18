## Default and refused policy results cannot expose a successful certificate.
import std/[cmdline, syncio]
import ../../src/state/[report_policy, guarantee_credentials, store]
let outcome = if paramStr(1) == "error":
  checkReportPolicy(default(VerifiedGuaranteeCredentials), default(StateStoreSnapshot), default(ReportPolicyConfig))
else:
  default(ReportPolicyResult[PolicyCheckedReports]) # Default contains no fabricated certificate.
discard outcome.value # Both alternatives must fail the success precondition.
