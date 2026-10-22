# Targeted account invariant certificates

Scope: join source-bound dependent footprint metadata, present preimage content
hashes and preimage request-key association. Each predicate is independently
bounded and checked under Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/accounts.tex`, eq:deposits and eq:preimageconstraints.

`sameStateInventory` compares initialized immutable capture owners. Copies of a
handle match; defaults, separate captures from the same snapshot, and independently
built equal mappings do not. The join requires all three original inventory owners
to match exactly. Default inputs preserve their specific missing predicate; a
cross-owner join returns `SourceMismatch`. Neither failure exposes a prefix.

Successful joined authority privately retains the original inventory and fixed
per-predicate work observations. Joining is constant bounded work with no payload
copies, output arrays or hashing. No trusted-root, economic, history-ordering,
global chapter semantic or complete STF validity claim follows from this type.

Native verification covers genuine joined success, every default input, copied
handles, separate equal-source captures, independently equal maps, both cross-owner
substitution positions, hash-disabled constant work, 1,000 ARC retirements and
strict payload/privacy/nominal guards. Run `make unit SUITE=state_account_invariants`.

Observed locally: selected native suite and 1,000 ARC cycles passed (152,320 bytes
before and after), with zero join-time hash calls. Two strict runtime guards,
five compiler rejections and genuine joined positive control passed; inventory
and pinned formatting passed.
