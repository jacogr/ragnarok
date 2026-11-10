# Stock HTTP request-head parsing

## Restoration

This change restores stock parser adoption from #2049 after the temporary rollback in #2054.
The November 9 Nimony nightly pinned in #2099 fixes the leak tracked in
[Nimony #2940](https://github.com/nim-lang/nimony/issues/2940). The original reproducer retains
zero bytes after 100 message retirements under checked ARC/Clang/ThinLTO on macOS ARM64.
The repeated-request UI cleanup regression from #2054 retains its original memory allowance.
Native listener tests and the Testnet RPC/browser shutdown workload cover application ownership.

Stock Nimony parses request heads for [RPC upgrades](rpc.md), [UI](ui.md), [MCP](mcp.md),
and [local management](management-rpc.md). Each service applies its own endpoint access
and body limits after parsing.

## Verification

The `rpc`, `ui`, `mcp` and `management_http` native suites cover their protocol and transport
owners. Focused additions cover stock tab refusals, LF/version acceptance, normalized lengths,
ordinary repeated fields, application selector ambiguity, heads above the former 4 KiB cap and
scanner resumption across packet boundaries. Formatting and verification inventory must pass
before publication. Linux runtime evidence remains separate from macOS results and Linux Smoke.
