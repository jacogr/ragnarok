# RPC observations across consecutive current adoptions

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. Independent TLS and
WebSocket processes qualify the live current command after each of two genuine consecutive
adoptions. The first child is gated until the original-parent subscription notification arrives;
a final empty response stays gated until all expected reads complete.

The subscriber requires three ordered parent/child notifications, exact slots and best block,
all retained state roots and sealed headers, and both child-parent links. Finality remains
unavailable, and autonomous state proof requests remain unavailable for download-current.
Only then does empty response three produce Exhausted with requested=3/adopted=2. Both native
processes join and the real listener must be released.

Memory, journal and managed runs share the same genuine expected heads. Disk cases strictly
reopen and compare every retained map and identity. Compaction stays off; no new runtime,
protocol, format or crypto interpretation is introduced. Run
`make unit SUITE=pvm_current_consecutive_rpc`. These remain authored implemented-scope witnesses,
not upstream current-pin full STF/Thin VRF parity. M1 framing and complete typed state
serialization remain separate scopes.

## Selected state after signed validator rotation

The same real integration assertions also run with the existing signed slot12 rotation and
genuine following children at slots13/14. Expected identities and complete physical maps come
from `currentRotatedSequenceFixture`; original first-epoch cases remain in the suite. The same
resource, refusal, ownership and durability checks apply after active/previous roster rotation.
This extends authored integration evidence without claiming independent full STF goldens,
current Thin VRF or supplied-logical qualification. No runtime/default/pin changes are made.

The rotation witness needs an explicit two-second bounded observer polling budget: the previous
200ms packet wait expired before the genuine slot12 notification, while the command subsequently
confirmed both adoptions. Other RPC helpers retain their default budget. Each invocation clears
its own stale controls and uses a fresh disk namespace; failure-only packet labels identify the
exact awaited request or notification. Production deadlines and RPC behavior remain unchanged.
