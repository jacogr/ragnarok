## External callers cannot forge package certificates or retag failed results.
import ../../../src/state/report_packages
let owner = default(ReportPackageResult[PackageCheckedReports])
discard owner.completed # Must fail before lowering.
