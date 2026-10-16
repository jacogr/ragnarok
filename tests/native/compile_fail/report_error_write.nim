## Safe code cannot bypass the private report state through error.
import ../../../src/codec/[composite, work_report, report_owned]
var value = default(ReportResult)
value.error = CompositeError.None
