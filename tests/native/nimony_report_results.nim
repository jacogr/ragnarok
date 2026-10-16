## Runtime-selected report result probes must fail on their intended success contract.
import std/[cmdline, syncio]
import ../../src/codec/[composite, work_report, report_owned, owned]

let useDefault = paramStr(2) == "default"
let empty = newSeq[byte](0)
let missing = default(OwnedReport)
let report = if useDefault: default(ReportResult) else: decodeReportBorrowed(empty, 2)
let header = if useDefault: default(ReportHeaderResult) else: decodeReportHeader(empty)
let owner = if useDefault: default(OwnedResult[OwnedReport]) else: decodeOwnedReport(empty, 2)
let info = if useDefault: default(OwnedResult[OwnedReportInfo]) else: ownedReportInfo(missing)
let prerequisite = if useDefault: default(OwnedResult[PackageHash]) else: ownedReportPrerequisite(missing, 0)
let lookup = if useDefault: default(OwnedResult[SegmentLookup]) else: ownedReportLookup(missing, 0)
case paramStr(1)
of "report-value":
  # Failed reports cannot expose a default core identity.
  echo uint64(report.value.core)
of "report-consumed":
  # Failed reports cannot expose fabricated cursor progress.
  echo report.consumed
of "header-value":
  # Failed fixed headers cannot expose a default shard count.
  echo uint16(header.value.erasureShards)
of "owner-value":
  # Failed captures cannot produce empty validated owners.
  echo ord(ownedReportInfo(owner.value).error)
of "info-value":
  # Failed metadata queries cannot report successful zero consumption.
  echo info.value.consumed
of "prerequisite-value":
  # Failed dependency queries cannot manufacture zero hashes.
  echo prerequisite.value.bytes[0]
of "lookup-value":
  # Failed dictionary queries cannot manufacture zero roots.
  echo lookup.value.segmentRoot.bytes[0]
else:
  # Unknown modes must not count as guarded failures.
  quit 2
