## Safe code cannot bypass the private report state through byteConsumed.
import ../../../src/codec/[composite, work_report, report_owned]
var value = default(ReportResult)
echo value.byteConsumed
