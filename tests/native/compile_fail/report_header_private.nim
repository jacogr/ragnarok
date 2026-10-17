## Safe code cannot bypass the private report state through decodedValue.
import ../../../src/codec/[composite, work_report, report_owned]
var value = default(ReportHeaderResult)
echo value.decodedValue.erasureShards
