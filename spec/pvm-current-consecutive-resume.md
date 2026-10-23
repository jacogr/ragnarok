# Current command restart from a persisted successor

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. A complete first command
adopts child one and closes every worker/IO/socket owner. A new command opens the original chain
configuration and the existing disk store, selects the persisted child, and receives children two
and three. The independent responder requires exactly those retained-parent request hashes.

Journal/managed layouts each run with implicit selected-head restart and explicit local-ancestor
projection. The fresh command reports requested=2/adopted=2; it never requests child one again.
A final strict reopen compares all four retained complete maps and block identities, with explicit
absence of chain finality. Managed automatic compaction stays off in this scope. The shared test
responder bounds at most four exact requests and joins on every exceptional exit.

Run `make unit SUITE=pvm_current_consecutive_resume`. This is implemented-profile authored evidence,
not published full current-pin STF/Thin VRF parity. M1 framing remains separate from complete
state serialization. No runtime, protocol interpretation or storage format changes are made.

All four native scenarios (eight distinct command lifetimes), focused semantic checking, inventory
and pinned formatting passed locally on macOS. Every reopened retained map matched exactly.

## Selected state after signed validator rotation

The same real integration assertions also run with the existing signed slot12 rotation and
genuine following children at slots13/14. Expected identities and complete physical maps come
from `currentRotatedSequenceFixture`; original first-epoch cases remain in the suite. The same
resource, refusal, ownership and durability checks apply after active/previous roster rotation.
This extends authored integration evidence without claiming independent full STF goldens,
current Thin VRF or supplied-logical qualification. No runtime/default/pin changes are made.
