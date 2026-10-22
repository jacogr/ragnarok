# Authenticated fallback across consecutive current children

Every genuine successor first receives an independently framed empty E4 response from identity A,
then succeeds through identity B under explicit two-peer/two-attempt policy. All three actual
parent requests are checked independently on each listener. One-attempt policy exhausts after A
with no adoption or request to B. Memory, journal and managed owners keep their explicit policy;
durable cases strictly reopen every retained map/hash/parent/slot and unavailable finality.

Run `make unit SUITE=pvm_current_consecutive_fallback`. Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. These authored witnesses do not
claim upstream full STF/Thin VRF parity or change runtime/default policy. M1 framing remains
separate from complete typed state serialization.
