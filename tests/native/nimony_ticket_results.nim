## Failed/default ticket operations must reject all reads of success-only progress.
import std/[cmdline, syncio]
import ../../src/codec/tickets

let useDefault = paramStr(2) == "default"
let empty: seq[byte] = @[]
let noRecords: seq[Ticket] = @[]
var bytes = newSeq[byte](0)
var records = newSeq[Ticket](0)
let written = if useDefault: default(TicketWrite) else: encodeTickets(noRecords, TicketLimit(0), bytes)
let decoded = if useDefault: default(TicketRead) else: decodeTickets(empty, TicketLimit(0), records)
let scanned = if useDefault: default(TicketRead) else: inspectTickets(empty, TicketLimit(0))
case paramStr(1)
of "written": echo written.written # Failed encodes have no committed output extent.
of "count": echo decoded.count # Failed decodes initialize no caller records.
of "consumed": echo decoded.consumed # Failed decodes cannot advance the caller's cursor.
of "inspect-count": echo scanned.count # Failed inspection cannot manufacture an empty success.
of "inspect-consumed": echo scanned.consumed # Failed inspection has no successful prefix.
else: quit 2 # Unknown fixture modes must not count as guarded rejections.
