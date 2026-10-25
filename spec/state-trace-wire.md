# Published RawState binary wire

Authority is the unmodified `traces/schema.asn` and `traces/convert.py` at vector
pin `23061ae1f9b51171c01387e7dde0f15794c98e24`, with GP compact natural framing.
RawState is the32-byte complete root followed by a variable sequence of31-byte
keys and variable value blobs. The new `state/trace_state` module accepts one
canonical scalar representation; there is no local checkpoint magic or fixed-E8
record-length fallback.

`decodeTraceState` validates a bounded prefix so a following TraceStep field remains
unconsumed. Its guarded owner retains the exact original bytes and a separately
recomputed immutable complete store. The ASN.1 sequence does not require sorted
records: copies preserve input order, deterministic store encoding uses lexical
key order, and duplicates always fail. Empty complete maps and present-empty values
remain explicit. Unknown hashed identities stay opaque; neither a matching root
nor successful parsing grants logical completeness, typed state qualification,
producer provenance or chain-adoption authority.

Preflight proves count, every key/length extent, per-value and total-value budgets
before retaining entry arrays or payloads. Complete-map construction enforces its
own topology and write-policy limits before hashing; a wrong root, primitive
failure or duplicate key returns a typed failure with no consumed-prefix payload.
Bounded detached output copies cannot mutate retained owners. Store export proves
its complete output extent before allocation. Nim allocation exhaustion retains
the existing fail-stop policy.

The independent corpus freezes322 requests before native execution:309 accepted
maps and13 typed refusals.295 current-profile full STF originals/successors come
from the independent allowance/incarnation/foreign-effect families. Three pinned
published binary pre-states match their exact JSON key/value records and roots;
historical service metadata is preserved as opaque bytes, never padded or repaired.
The remaining cases cover unsorted records, empty values/maps and compact blob
boundaries127/128 and16383/16384. Each accepted result compares original wire,
deterministically ordered wire and the entire independently encoded local checkpoint.
Malformed roots, duplicate keys, noncanonical/huge naturals, truncation and a short
prefix ceiling compare typed refusals.

Native units cut every byte boundary and output ceiling, exercise independent
store limits and mutate both input and copied output after ownership capture.
Compiler privacy fixtures forbid access to the raw owner and result payload.
Pinned formatting is checked twice for idempotence, with focused semantic, native,
independent-reference and inventory verification. Local ARC/Clang evidence is not
exact-head Linux CI. This layer supplies RawState framing; composed TraceStep block
import, explicit profile binding and external client STF comparison remain next.
