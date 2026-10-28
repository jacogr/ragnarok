# Application orchestration

[Source guide](../README.md) · [Application design](../../docs/design/app.md)

This folder joins validated configuration, optional services and explicitly selected complete-state
work. The process entry point is [`../ragnarok.nim`](../ragnarok.nim); these modules receive owned
configuration rather than reading command-line globals themselves.

| Modules | Responsibility |
| --- | --- |
| [`cli_defaults.nim`](cli_defaults.nim), [`cli_catalog.nim`](cli_catalog.nim), [`cli_commands.nim`](cli_commands.nim), [`cli_help.nim`](cli_help.nim) | Shared defaults, named command grammar and grouped [CLI help](../../docs/cli.md) |
| [`options.nim`](options.nim), [`services.nim`](services.nim) | Parse configuration atomically and own telemetry, RPC, MCP, UI and optional canonical state through startup and shutdown |
| [`chain.nim`](chain.nim), [`candidate.nim`](candidate.nim), [`handoff.nim`](handoff.nim) | Retain the selected complete-state head, prepare finalized candidates and acknowledge deferred adoption |
| [`block_input.nim`](block_input.nim), [`block_download.nim`](block_download.nim) | Bound received block bytes and hand them to explicit preparation outside transport callbacks |
| [`download_command.nim`](download_command.nim), `download_policy*`, [`download_schedule.nim`](download_schedule.nim) | Configure the one-child download command, explicit resource budgets and bounded peer rotation |
| [`preparation_worker.nim`](preparation_worker.nim) | Own one execution worker and its exclusive input/chain lease through collection or joined shutdown |
| `checkpoint_*` | Capture detached application envelopes, bound file I/O and coordinate checkpoint publication workers |

The development proof peer accepts `server`, `client`, retained `mesh` and explicit `download`
commands. Run `build/ragnarok --help` after `make`; the [networking guide](../../docs/networking.md)
and [download startup contract](../../spec/application-download-startup.md) describe their inputs.
These bounded paths do not provide a complete production node, consensus or validator service.

Optional [telemetry](../telemetry/README.md), [WebSocket RPC](../rpc/README.md) and
[browser UI](../ui/README.md) and [MCP tools](../mcp/README.md) have their usage and scope documented in their own folders.
Canonical state requires explicit state configuration and mutation budgets. Worker leases keep
plain ARC graphs exclusive; native callbacks retire before the enclosing service owners close.

The [application contract](../../spec/application.md), [chain contract](../../spec/application-chain.md),
[preparation lease](../../spec/application-preparation-lease.md) and
[checkpoint contract](../../spec/application-checkpoint.md) record exact ownership, verification
and remaining integration boundaries.

[`ancestor_response.nim`](ancestor_response.nim) validates bounded descending block
responses against a known child's exact sealed parent chain;
[`ancestor_receiver.nim`](ancestor_receiver.nim) owns fragmented E4 bytes and both
FIN gates. The download command can extend local/file inputs with explicit
`--download-remote-ancestors COUNT` context before child requests. See the
[remote acquisition contract](../../spec/application-remote-ancestors.md) and
[operator guide](../../docs/download-ancestors.md) for bounds, retry behavior and
canonical-history separation. Alternatively, `--download-discover-ancestors COUNT`
receives each child first and fetches only certified missing context within one
whole-run allowance. Its prepared input resumes after worker/connection retirement;
see the [state context contract](../../spec/state-ancestor-context.md).
