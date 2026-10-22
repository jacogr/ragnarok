# Same-turn RPC proof lease during current download expiry

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. This layer qualifies
existing current-loop lifetime guards with real WebSocket admission and a genuine native worker;
it changes no implementation, resource policy or dependency pin.

The hypothesis is concrete: an active current input reaches its exact attempt deadline, then
Services admits a queued RPC proof inside that dispatcher turn. Retrying after Services returns
would retire aliases still borrowed by the worker. The post-tick proof guard must yield before
this retirement. A deterministic witness can select this ordering directly, so no speculative
scheduler model is needed.

The native suite reserves a proof intent through the actual WebSocket while a current input is
Receiving. One dispatcher turn at the exact deadline starts the real proof, leaves Receiving
unchanged, and keeps RPC paused. Immediate joined close and separately observed-Done joined close
must end the lease before retiring input, emit the same request's terminal stopped notification
without unwanted proof bytes, and preserve every original canonical map entry and retained head.
This is a selected lifetime boundary, not exhaustive scheduling or production proof RPC admission
for the download command (whose startup policy remains unchanged).

Run `make unit SUITE=pvm_current_download_rpc_lease`. Both immediate and observed-Done native cases, focused semantic checking, pinned formatting
and inventory passed locally on macOS;
these witnesses do not claim Linux CI, complete state serialization or full JAM/ThinVRF parity.
