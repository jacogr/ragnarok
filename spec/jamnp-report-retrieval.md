# Work-report retrieval

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE136, and GP
`3861aed15d7d016a3a416e14e61fc67dddf6daec` full WorkReport encoding and Blake2b256 identity.
No dependency, toolchain or specification pin changes.

CE136 uses an exact 32-byte report hash request and request FIN, followed by exactly one E4 bare
WorkReport and response FIN. Guarantee evaluation slots, credentials, assignment registration
and extrinsic/queue counts are excluded from the response. Unknown content resets the exact
requesting stream; an empty successful reply never stands in for a missing report.

`ReadKind.Report` uses the existing authenticated fixed-request node route, bounded native client,
global64/per-peer2 read reservations, deadlines and Services worker lease. Native callbacks retain
only bounded wire bytes. State lookup, report hashing and complete decoding run outside callbacks.
The ordinary `node` command inherits this route through its existing managed actor.

The canonical responder reuses `ChainView.reportAt` and the nominal `WorkReportHash`. Lookup
searches only the selected head's C10 availability assignments, then C14 ready queues for an
ordinary miss. It preserves existing complete-parent validation, actual active-roster credential
framing, 1MiB chapter bounds and bounded queue counts. It does not widen a request into history or
an archive. A malformed C10 cannot be hidden by a valid C14 report. Only a successfully retained
report is re-encoded, within the existing8MiB aggregate framed reply ceiling. Source failures and
resource refusals expose no report prefix and preserve their reason classes.

Checked outbound reads hash the entire response body against the exact requested identity and
decode one complete canonical report under the independently captured local core profile. A
matching hash cannot authorize malformed encoding, a report for an out-of-profile core or a
valid report followed by a suffix. Jobs capture fixed local metadata and fresh wire bytes, with
the same exact cancellation/Done/collection/join lease as other checked reads. `CheckedReadReply`
exposes an immutable `OwnedReport` only in its guarded Report alternative; genuine failed codec
causes are retained as `ReportFailure`. A content-addressed report grants no guarantee, judgment,
execution, audit or availability certificate.

Verification:

- `jamnp_report_retrieval`: independent393-byte Python-oracle report fixture and fixed Blake2b256
  identity `283bc0dbb9109d0a2a7ae37ff661c5889f4dc632170e9e2acbf3113d51365fca`;
  C10 and C14 canonical sources; unknown content, malformed parent/suffix and lookup limits;
  missing local profile, byte budgets and matching-hash wrong-core reports; every incomplete
  report prefix with its own matching hash, complete-body suffix and immutable extraction.
- Both sources run through actual Services and authenticated TLS: exact request FIN before work,
  independent bare-report reply bytes, unknown-report reset and a healthy sibling after selector
  admission, managed outbound success and corruption refusal, complete owner lifetime after
  shutdown and preservation of a foreign report-worker lease. Existing selector and physical-close
  quotas remain intact.1000 direct verification cycles provide fresh balanced ARC evidence.
- `jamnp_read_validation` and `jamnp_node_service` retain existing read semantics, stream quotas,
  cancellation, paired-owner and IPv4/IPv6 consumer coverage. Formatter and application build
  verify the integrated surface.

Report caches populated by CE135 distribution and audit/judgment work are still needed beyond
canonical C10/C14 retention. Preferred selection of peers that publish/forward negative judgments
belongs to the CE145 runtime integration. Those obligations and complete auditor operation remain
open; this layer provides the bounded authenticated request/response path and checked content.

The existing raw read-client exchange consumer includes an independent literal CE136 selector/32-byte request and withheld-response-FIN witness. Adding a sparse read kind must update this exhaustive test helper as well as production dispatch.
