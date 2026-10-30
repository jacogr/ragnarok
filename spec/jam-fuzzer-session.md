# JAM fuzzer-v1 session boundary

Authority is the pinned jam-conformance/jam-fuzzing revision
3a488be18fe7b94aa1d35bd0d6f8981ec5bbefae, fuzz-proto/README.md connection,
message response, error and session-lifetime rules, and fuzz-v1.asn feature bits.
The existing current Gray Paper pin and Tiny structural profile remain unchanged.

This increment implements incremental length-prefixed input and deterministic
session ordering. It runs no socket listener or STF; host execution remains an
explicit action with a unique opaque request ticket. Completion tests cover every
frame split, concatenated frames, exact profile negotiation, request ordering,
cross-session and reused tickets, malformed frames, feature intersection and
continuation after a consensus import rejection.

A fresh session requires PeerInfo first. Protocol version 1 and the exact
configured JAM major/minor/patch must agree; application identity is informational.
Supported ancestry/fork bits are intersected with the peer declaration. Unknown
remote bits grant no features. A target may advertise only features it actually
implements; the constructor rejects unknown local bits. The handshake reply
preserves the target's own declaration rather than rewriting it to the intersection.

Exactly one Initialize follows the handshake. Nonempty supplied ancestry requires
negotiated ancestry support. Initialize, ImportBlock and GetState produce immutable
request tickets. Only that session's outstanding ticket can authorize completion;
a wrong/reused ticket, concurrent request or wrong response terminates the session.
Initialization requires StateRoot, import requires StateRoot or Error, and state
lookup requires State. Only genuine consensus import rejection is represented by
Error; the host closes for missing context, unsupported state, resource failures
or other internal faults. A successful import or import Error both permit the
next sequential request. No backend result is inferred by this layer.

The frame reader takes explicit codec limits and validates the four-byte
little-endian length before allocating one payload. It consumes no bytes beyond
one frame, reports its consumed prefix, and leaves any following frame in caller
storage. Fragmentation at any prefix/payload position and empty reads preserve
assembly. Successful decode detaches the complete message before reader reuse;
malformed messages and invalid lengths permanently retire that reader. Connection
EOF/timeout and partial-output handling belong to the following transport layer.

The backend must treat Initialize as the protocol's explicit fuzz seed: its full
map is accepted independently of the supplied header's parent-state commitment.
This is separate from production genesis/checkpoint trust. An opaque captured map
still does not prove raw logical identities, sufficient ancestry or successful STF
execution. Those backend obligations remain open. Missing polkajam-fuzz availability
blocks live campaign validation, not this interface implementation.
