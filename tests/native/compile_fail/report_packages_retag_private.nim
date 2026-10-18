## External callers cannot forge package certificates or retag failed results.
import ../../../src/state/report_packages
let owner = default(ReportPackageResult[PackageCheckedReports])
discard owner.status # Must fail before lowering.
