## Default and refused anchor results cannot expose completed report batches.
import std/[cmdline, syncio]
import ../../src/state/report_anchors
import ../../src/codec/header
let outcome = if paramStr(1) == "error":
  checkReportLookupAnchors(default(RecentAnchoredReports), default(OwnedHeader), [], default(AncestorConfig))
else:
  default(ReportAnchorResult[AnchoredReports]) # No default successful chain.
discard outcome.value # Both alternatives must fail the success precondition.
