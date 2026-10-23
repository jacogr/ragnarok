# Logical continuation across proven storage identity changes

Scope preserves Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`; no protocol, storage-format or root-policy change.

`continueCurrentStorage` accepts an original configured `SelectedLogicalParent` or prior completed
`CurrentLogicalState` and a genuine prepared current update carrying its own selected storage
history. It reuses strict identity binding: only success or the explicit new/missing-identity refusal
may advance after exact physical parent, complete ordered view/finality and full Parameters checks.
Those identity-set refusals grant no existing unchanged-identity certificate. All other refusals
preserve their genuine failed result. No supplied successor declarations or replacement history are
accepted.

Original retained raw keys seed the namespace; genuine selected storage facts introduce new raw
identities and authorize removed original storage keys. Identical repeated identities coalesce;
physical equality with different raw keys refuses. Untouched identities survive, including empty
raw keys and present-empty values. Final presence/value comes from the actual complete successor,
not from a touched-key diff. Panic/checkpoint and parallel annulment have already selected matching
producer facts. An unexplained removed key refuses. Service creation/ejection, preimage/request
identity changes and non-guest identity additions remain unsupported and fail local reconstruction
or mandatory complete-map matching.

An independent scratch policy admits worst-case original/produced identity descriptors, all copied
raw keys and request-key slots before scratch allocation. A planning-work cap bounds service search
and duplicate comparisons. The entire exact output descriptor/key/value/codec-wire ledger passes
before actual payload copying; request-key hashing remains mandatory and typed. Reconstructed
metadata and histories pass existing exact codecs. Original-current profile/all-global qualification,
whole-map matching and independently retained raw-key capture must all succeed before a
`CurrentLogicalState` escapes. Each stage keeps its own explicit policy and genuine refusal.

Services overloads exclude all three native graph leases through cancellation/Done until matching
collection or joined shutdown. The operation grants no adoption, finality or general mutation-log
certificate. Opt-in producer capture is required even for an enabled empty history.

Completion: the native suite covers real worker growth, deletion, uncheckpointed panic and
checkpointed panic; untouched/empty raw identities; refusal of a new request namespace; foreign
physical parents; early quotas and genuine backend failure; late profile/global/raw capture quotas;
repeated actual children; and 1,000 full reconstruction/current qualification ARC retirement cycles.
Strict result/privacy guards, all managed lease alternatives, existing identity/current logical
consumers, inventory and both formatting gates apply. M1 framing is complete; full independent
current-schema STF, current Thin VRF and ambiguous privilege gates remain open.
