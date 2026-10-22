# Current command confirmed RPC observations

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. This test-only layer
qualifies the actual read-only RPC listener alongside current native execution and durable adoption.
It changes no implementation, protocol interpretation, pin or proof-admission policy.

Two independent forked processes serve authenticated TLS and observe the actual command WebSocket.
The first child response stays gated until subscribeBestBlock yields the original parent. The
observer then requires the actual child notification, exact slots, best block, both complete-state
roots and sealed headers, the exact parent relation and unavailable finality. Autonomous proof
requests remain method-unavailable for download-current. Only after these observations finish does
the responder release a second empty response. The command must report Exhausted with exactly
one adoption out of two requests, and both independent child processes must join successfully.

Memory and managed-disk command runs use a genuine independently composed current child.
The managed case strictly reopens and compares every state entry and retained history. TLS request
bytes identify the original parent followed by the independently hashed actual child; an RPC
success marker alone cannot supply this authority. Listener rebind proves completed teardown.

Run `make unit SUITE=pvm_current_download_rpc`. Both memory and managed-disk native cases, focused semantic checking, inventory and pinned
formatting passed locally on macOS.
Selected native/API/RPC witnesses remain distinct from full-plan E2E and exact-head Linux CI.
M1 framing is complete separately from full state serialization; full JAM/ThinVRF parity and
two successful consecutive current children remain outside this increment.
