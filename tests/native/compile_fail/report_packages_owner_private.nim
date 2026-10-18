## External callers cannot forge package certificates or retag failed results.
import ../../../src/state/report_packages
let owner = default(PackageCheckedReports)
discard owner.data # Must fail before lowering.
