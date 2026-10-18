## External callers cannot forge completed anchor certificates or retag failed results.
import ../../../src/state/report_anchors
let owner = default(RecentAnchoredReports)
discard owner.data # Must fail before lowering.
