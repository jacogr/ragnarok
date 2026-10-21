# Remote ancestor context

Scope: bounded CE 128 descending-inclusive responses supply immutable sealed parent
headers for existing report admission. Authority is pinned JAMNP-S revision
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, `simple.md` CE 128, and the existing
GP 0.8.0 block/header codecs. Pins and protocol behavior do not change.

A request binds the exact known child's parent hash, its slot and an explicit
positive E4-sized maximum. Response payload is an uncounted sequence of complete
GP blocks. Empty and shorter-than-maximum responses are valid protocol outcomes;
empty exposes no headers. Every sealed header must hash to the previously expected
parent and have a strictly older slot. Decode the complete extrinsic to determine
block boundaries; header identity alone does not validate historical execution,
signatures, extrinsic commitments or finality. Existing report admission keeps its
own complete linkage, profile, lookup-child and state-root checks.

Response bytes, per-block codec resources, retained header bytes and header count
have independent explicit limits. Check arithmetic and descriptor bounds before
allocation/access. Failures expose no captured prefix and retain exact nested
block codec reasons. Returned sequence storage is independent of the immutable
response owner. No StateStore, storage, Services, finality or canonical history is
modified by acquisition.

Completion witnesses: independent literal request bytes, genuine descending
chains, exact/short limits, shorter responses, empty/truncated/suffixed bodies,
wrong first identity, reordered/duplicate/unrelated parents, strict slots, default
owners/results, late failure atomicity, detached ownership and repeated ARC release.
Streaming FIN, transport retirement, command wiring and actual network operation
remain separate layers. M1 framing is complete; full serialization/JAM parity remain open.

## Response evidence

The focused native `application_ancestor_response` suite passes, including literal
E4 request bytes at the full u32 maximum, genuine composed three-parent responses,
shorter valid replies, duplicate parents, late block truncation and an extra
message/body suffix. Independent copies cannot replace retained header owners.
Its final 1,000-cycle success/late-refusal ARC observation retains 358,512 occupied
bytes before/after. Four strict runtime extraction failures with genuine positive
controls, six private-field rejections and verification inventory pass locally.
Evidence: `build/remote-ancestors-{unit,guards,inventory}.log`. This is local
macOS/ARC evidence, without a Linux CI or complete JAM parity claim.
