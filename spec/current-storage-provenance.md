# Current-bound producer storage evidence

Scope preserves Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vector
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`; no protocol, root policy or storage format changes.

`CurrentCandidateLimits.storage` opts into bounded selected storage history during genuine current
update preparation. Zero entry capacity explicitly disables this optional observation. Enabling it
also requires producer raw-key capture for every surviving executed invocation, under independently
selected guest policies. Missing capture and whole-history resource failures return guarded exact
`StorageHistoryFailure` reasons; neither private candidate state nor view escapes on refusal.

Preparation follows its actual successful consensus/composition chain to the original completed
current sequence. It captures once without guest replay and stores that immutable history inside
`PreparedCurrentChainUpdate`. `hasStorageHistory` distinguishes disabled/default updates from enabled
empty histories; `currentUpdateStorageHistory` requires that capability. There is no public setter
or caller-supplied replacement history. Exact original parent, full prior/posterior views, full
Parameters, selected state and child provenance retain their existing contracts.

Opt-in history retains original producer history under its frozen execution bounds in addition to
its admitted raw-key/row ledger; it is an acyclic owner, not a detached value-diff certificate.
The candidate policy is frozen through the existing native preparation input, and matching actual
collection returns the evidence on that worker's genuine update. Existing disabled consumers retain
their behavior and all graph lease/collection rules still apply. Optional evidence failure remains
separate from protocol invalidity and never installs state.

Completion: `make unit SUITE=current_storage_provenance` covers actual native preparation and
collection, a real newly created key7, exact original parent, detached copy mutation, disabled/raw
capture refusal, late history quota refusal, no adoption and 1,000 balanced history observation
retain/retire cycles. Strict default/reason/capability guards, privacy rejection, affected candidate/
worker consumers, inventory and both formatting gates apply.

Next consumer: use this update-owned selected storage history with a qualified original logical
parent to propagate only proven storage identity changes, followed by complete successor matching.
Creation/ejection, request/preimage and non-guest identity changes remain separate producer work;
no general supplied-delta API or full logical manifest is claimed. M1 framing is complete;
independent full current-schema STF, current Thin VRF and ambiguous privilege gates remain open.
