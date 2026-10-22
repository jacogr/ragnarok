# Explicit economic parameter selection

Scope: bind the exact deposit-per-account, deposit-per-item and deposit-per-byte
fields from an explicitly supplied immutable `Parameters` snapshot. Pinned Gray
Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, accounts eq:deposits and the existing
fetch(0) parameter schema supply the field meanings. Existing `Parameters.valid`
checks remain the documented population/clock subset, not full chain validation.

Capture refuses invalid/default parameters before selecting rates. Successful
profiles privately retain the fixed complete parameter value and exact nominal
rates; default profiles expose neither. Equality checks initialized full parameter
values through their unchanged fixed encoding, including non-deposit fields.
Valid explicitly zero rates remain usable; default zero configuration does not.
No heap ownership, hashing, network/profile discovery, trusted-root selection or
existing PVM/Services behavior changes occur. The caller remains responsible for
choosing the correct chain configuration.

Native coverage uses independent literal fetch offsets, exact and maximum rates,
valid zero rates, full-profile equality versus a non-rate difference, input buffer
mutation, immutable copied rates, invalid/default handling and strict runtime/
private/nominal guards. Run `make unit SUITE=state_economic_profile`.

Observed locally: selected native suite, 2 strict runtime guards, 5 exact compiler rejections and genuine positive control passed; inventory and pinned formatting passed.
