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
