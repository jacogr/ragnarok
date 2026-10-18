# External-input fetch

Scope: fetch selectors 3–6 over explicitly supplied extrinsic preimages and imported
segments. Normative source: Gray Paper 0.8.0, gitlink
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`, General
Functions, Omega_Y selectors 3–6 and Refine's input tables; `text/definitions.tex`,
CgasYc/CgasYl entries 3–6, Csegmentsize, Cmaxpackageitems, Cmaxpackagexts and
Cmaxpackageimports. Data segments contain exactly 4,104 octets.

Selectors 3/5 use r11 as the work-item row and r12 as the entry index. Selectors 4/6
use the captured current work item and r11 as the entry index, ignoring r12. All
indices are compared at full uint64 width before narrowing. Missing tables, missing
current identity for 4/6, and guest indices outside a selected table return NONE.
A present empty extrinsic returns zero. Returned values are raw preimage/segment
bytes, with no prefixes, commitments or proofs.

Extrinsic selectors 3/4 cost 85 + ceil(96*r9/1024); imported-segment selectors 5/6
cost 171 with no per-byte charge. Charging uses requested length even for absent or
clipped values. Existing fetch gas-deficit, natural empty-interval, atomic memory
copy and typed local-copy refusal contracts apply unchanged.

withFetchInputs takes a FetchInputs description and a nominal FetchInputLimit.
Both tables and the current-item identity have independent explicit presence.
FetchItemIndex separates caller-supplied current identity from ordinary integers;
FetchSegment is a nominal fixed 4,104-byte array. Absent table payloads are ignored.
An explicitly absent current index is ignored. A present current index must fit
both selected tables; otherwise capture returns InvalidContext before allocation.
This caller error differs from guest index misses, which are protocol absence.
Present empty tables are valid when no current identity is supplied.

Capture preflights at most sixteen rows per selected table, at most 128 extrinsics
and 3,072 imports across all rows, and aggregate selected bytes against the local
cap. Empty rows/preimages still consume bounded descriptors. Subtract-after-compare
accounting avoids aggregate size overflow; import byte multiplication follows the
fixed count bound. Only then are all descriptor levels, blob bytes and segment
arrays copied. Private acyclic ownership exposes no writable storage. Source storage
must remain stable until capture returns and may then be changed or destroyed.
Replacing/clearing inputs preserves package, entropy and trace snapshots; package
attachment/clearing likewise preserves inputs. Older handles remain unchanged.

This operation validates shape, resource bounds and current-index safety, not data
authenticity. The invocation layer must supply verified preimages/segments in work-item
manifest order and ensure row/entry counts and current identity correspond to the
invocation's package. Package and input capture remain independent; neither silently
rewrites the other. Full refinement invocation assembly and data-availability proof
verification are outside this increment.

Tests use original ragged tables with distinct values, empty preimages/rows, first/last
segment bytes, and independent expected selections. They cover all presence combinations,
full-width indices, ignored r12, exact/short funding, maximal lengths/offsets, complete
segment copies across pages, atomic permission failure, local copy caps, source mutation,
package/input attachment order, minimum/exact/over-limit metadata and byte budgets,
maximum imports, real host dispatch and fresh 1,000-cycle ARC evidence. Runtime probes
reject failed capture payload extraction; compiler guards enforce private snapshot
storage and nominal index/limit inputs. No upstream code or vectors are copied.

Fetch selectors 1–13 are implemented. Constants (0), accumulation inputs (14–15),
complete invocation assembly and the positive gas-domain gate remain open. Next
bounded increment: protocol-parameter fetch selector 0 with independent byte-layout
witnesses against pinned constants.
