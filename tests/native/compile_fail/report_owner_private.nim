## Safe code cannot bypass the private report state through data.
import ../../../src/codec/[composite, work_report, report_owned]
var value = default(OwnedReport)
discard value.data
