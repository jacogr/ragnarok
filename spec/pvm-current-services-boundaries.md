# Current Services disk failure and joined shutdown

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive.
These witnesses qualify the [current Services durable adapter](pvm-current-services-disk.md)
without changing protocol interpretation, runtime code, pins or storage formats.

The native suite uses genuine signed current execution and independently serialized complete parent
state. Immediate close may join an entered operation or stop a queued operation. Its actual retained
receipt selects the only valid restart expectation: the complete parent for no executed IO, or the
complete child for confirmed success. Both single-file and managed layouts are tested. A separate
synchronized-Done close must preserve successful IO; Done alone still holds the exclusive RPC/graph
lease before joined close. Strict restart compares the exact head and every expected state key/value.
The immediate-close case does not claim both scheduler outcomes occurred in any particular run.

Enabled RPC closed before staging must yield RpcRefused, unchanged canonical identity and byte-exact
unchanged disk contents. Staging/admission/IO remain uninitialized. A later strict startup must
recover the complete parent; enabled RPC never becomes canonical-only publication.

A forked writer lowers only its own RLIMIT_FSIZE after complete startup and real current preparation.
SIGXFSZ is handled without allocation so actual partial journal mutation returns the exact
StoreFailure/FileFailure/IoFailure chain. Services reports DurabilityRefused, keeps its canonical
parent, disables preparation/proof work and rejects another current enqueue as Unavailable. A later
tick may not extend the failed journal. Joined close retains the actual error. The parent then proves
strict restart refuses the partial tail without modifying it or exposing canonical state. The parent
runner's resource limits and signal policy remain unchanged; every preceding native worker lifetime
has joined before fork.

Run `make unit SUITE=pvm_current_services_boundaries`; the existing current disk integration suite
also exercises the shared setup helper. The selected profile retains assertions and bounds checks
under ARC/Clang. Managed file-failure variants, post-commit RPC refusal and current maintenance
interleavings remain separate work. These witnesses do not establish exact-head Linux CI or
production transport/full JAM/ThinVRF parity.

Local macOS validation passed: the boundary suite and affected current disk integration suite,
including its four layout/RPC combinations, ran serially under ARC/Clang. Focused semantic checking,
inventory and changed-source pinned formatter idempotence also passed. Production sources are
identical to the already-qualified parent layer; their existing guards remain applicable.
