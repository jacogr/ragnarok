## Safe code cannot bypass the private report state through status.
import ../../../src/codec/[composite, work_report, report_owned]
var value = default(ReportHeaderResult)
value.status = CompositeError.None
