import ../../../src/codec/work_report
# An anchor time cannot silently become a lookup-anchor time.
let wrong = ReportHeader(anchorSlot: LookupSlot(0))
discard wrong
