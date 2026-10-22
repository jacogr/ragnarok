# Explicit current download command

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. This layer exposes
`download-current` through the production entry point and a separately typed command API.
It requires the complete `ragnarok-current-download-policy-v1` policy, selected complete chain,
and authenticated peer pins. The policy's explicit discovery boolean must match the command's
ancestor-discovery selection; startup never infers missing resource caps or accepts a legacy policy.

The command owns the native current dispatcher, original-history discovery and bounded shutdown.
Only consumed current Services adoption increments progress or changes the next parent. Existing
peer/deadline/ancestor caps and the maximum 64-block command budget remain explicit. Every exit
joins retained worker/disk lifetimes before releasing contexts, and preserves already adopted
progress. Disk confirmation comes from the same Services IO owner. Services proof-RPC startup
policy is unchanged.

`make unit SUITE=pvm_current_download_command` passed policy/options refusals and five real TLS
API cases: memory and journal/managed disk with RPC disabled/enabled. Each disk case strictly
reopens and compares every independently composed state entry. The private-result compiler guard,
affected legacy options/discovery/startup suites, focused semantic checks, inventory and pinned
formatting passed. `make build` produced the actual integration/offload executable locally on
macOS. Actual executable process/output qualification follows in a separate layer; these API
results do not claim that coverage, Linux CI, complete state serialization or full JAM/ThinVRF parity.
