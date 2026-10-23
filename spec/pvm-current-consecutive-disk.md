# Consecutive current durable history

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. The same two genuine
current children exercise journal/managed publication with RPC disabled/enabled. Each combination
covers two successful adoptions and a separate explicitly short C3 history ceiling that refuses
the second child after one confirmed adoption. No runtime, format, profile or pin changes occur.

All eight command cases use real authenticated TLS and the actual Services IO-owner receipt.
Strict restart compares every retained block hash, parent, slot and every state key/value, not
only the latest root. Refused second preparation restores exactly the original parent plus first
child, with no second child or invented finality. Managed compaction is explicitly disabled so
this layer isolates repeated publication; maintenance scheduling is separate qualification.

Run `make unit SUITE=pvm_current_consecutive_disk`. Complete raw-map preservation does not claim
published current-pin STF/Thin VRF or complete typed-state serialization parity. M1 framing
remains complete and separate from those gates.

All eight native cases, focused semantic checking, inventory and pinned formatting passed locally
on macOS under checked ARC/Clang. Every restored historical map matched its genuine fixture head.
