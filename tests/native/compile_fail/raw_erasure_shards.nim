import ../../../src/work_report
# A host integer cannot implicitly identify an assuring validator-set cardinality.
let wrong = ReportHeader(erasureShards: 6'u16)
discard wrong
