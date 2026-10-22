# Current request reservations without absent-payload allocation

This evidence increment follows current Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` including the accepted request-domain fix:
lengths are strictly below2^32-2. Complete one-service fixtures reserve lengths
0,1,127,128,0xfffffffc and0xfffffffd with no present preimage. Reserved0xfffffffe and
0xffffffff continue to refuse before key hashing through existing canonical codecs.

Metadata independently charges2items and81+length octets. At the largest valid
length this is4,294,967,374octets and a funded12,884,902,226 minimum under explicit
rates100/2/3. Actual complete storage remains a fixed request identity/history and
metadata; retained inventory descriptor bytes stay constant across lengths.
Whole-account plans/content execution admit zero preimage count/bytes and perform
zero content hashes with the backend refused. Exact economic observations remain
funded without allocating the absent advertised blob.

This is bounded current-pin account consistency/resource evidence, not full PVM
fresh-solicit/genesis reachability or complete upstream state/STF parity. Existing
production codecs, policies, guards, root authority and storage formats are unchanged.
Run `make unit SUITE=state_account_request_boundaries`.

Observed locally: selected native suite, inventory and pinned formatting passed. Existing production contract/privacy controls are unchanged.
