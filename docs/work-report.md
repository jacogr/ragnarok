# Complete work-report APIs

All three implementations follow [the pinned wire and structural contract](../spec/work-report.md).
The new modules reuse the existing canonical natural, byte-string and work-digest codecs.

| Operation | Nim | Odin | Mojo |
| --- | --- | --- | --- |
| Decode borrowed prefix | `decodeReportBorrowed` | `decode_report_borrowed` | `decode_report_borrowed` |
| Encode borrowed value | `encodeReportBorrowed` | `encode_report_borrowed` | `encode_report_borrowed` |
| Preflight borrowed value | `measureReportBorrowed` | `measure_report_borrowed` | `measure_report_borrowed` |
| Capture immutable owner | `decodeOwnedReport` | `decode_owned_report` | `decode_owned_report` |
| Read fixed/count metadata | `ownedReportInfo` | `owned_report_info` | `owned_report_info` |
| Read one digest's metadata | `ownedReportDigest` | `owned_report_digest` | `owned_report_digest` |
| Read one prerequisite | `ownedReportPrerequisite` | `owned_report_prerequisite` | `owned_report_prerequisite` |
| Read one lookup pair | `ownedReportLookup` | `owned_report_lookup` | `owned_report_lookup` |
| Copy retained payload | `copyReportBlob` | `copy_report_blob` | `copy_report_blob` |
| Re-emit retained bytes | `encodeOwnedReport` | `encode_owned_report` | `encode_owned_report` |
| Final owner release | Automatic ARC | `release_report` | `release_report` |
| Build guarantee message | `guaranteeMessage` | `guarantee_message` | `guarantee_message` |

Nim modules are `nim/src/work_report.nim`, `nim/src/report_owned.nim` and
`nim/crypto/guarantee.nim`. Odin uses the corresponding files under `odin/codec` and `odin/crypto`.
Mojo uses `mojo/codec/report.mojo`, `mojo/codec/report_owned.mojo` and `mojo/crypto/guarantee.mojo`.
Owner failures reuse the existing ownership result domain in Nim/Odin and checked variants in Mojo.

Provide the chain's core count explicitly: two for the pinned tiny profile, 341 for full.
A borrowed decoder returns one complete prefix; check `consumed == input length` when the
application expects a standalone report. Input must remain alive and stable during borrowed use.
Successful digest payload spans are rebased to the original complete input, not child slices.

At application boundaries, capture an immutable owner and use its metadata/extraction functions.
Payload index zero selects authorization output. Index `i + 1` selects digest `i`'s successful
output; payload-free work errors reject extraction. Empty successes remain valid empty blobs.
Metadata getters return owned fixed fields and payload lengths, never detached source coordinates.
The owner re-emits only its consumed prefix, so unrelated trailing data is never retained.

Nim handle copies automatically retain the private acyclic ARC storage. Odin/Mojo handle copies
are borrowed aliases: one original owner must release exactly once after all aliases stop using
it. Odin's supplied allocator must outlive the owner. Do not use aliases after release.

Every encoder preflights all counts, ordering, spans, common payload budget, capacity and pool
aliasing before writing. Failures contain only a typed reason; check/select success before reading
values or consumed/written metadata. No untrusted count drives a borrowed allocation.
Nim allocation exhaustion and Mojo native List exhaustion retain their existing runtime policies;
Odin exposes allocator refusal, and Mojo explicitly handles foreign metadata allocation refusal.

For guarantee verification, re-emit canonical retained report bytes, build the normative signing
message, then call the existing ordinary Ed25519 verifier for each credential. The message builder
accepts already canonical bytes; it does not parse, authorize validators or enforce timeslots.
The composed tests use two distinct ordinary keys. They do not resolve the documented provider
acceptance-policy difference for exceptional Ed25519 encodings or implement guarantee state rules.
