## A package identity cannot be initialized with an exported-segment commitment.
import ../../../src/codec/work_report
let wrong = ReportHeader(packageHash: SegmentRoot())
discard wrong
