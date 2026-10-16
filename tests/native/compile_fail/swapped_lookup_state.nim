import ../../../src/codec/work_report
# A supplied anchor state cannot silently become a lookup-anchor state.
let wrong = ReportHeader(lookupStateRoot: StateRoot())
discard wrong
