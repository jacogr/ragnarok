# Stock HTTP parser adoption: deferred after cleanup failure

The initial adoption of unmodified `std/http/httpparse` and `std/http/httpmsg` at Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` was merged in #2049. Master E2E / Testnet then
failed at peer shutdown after the RPC/browser exchanges succeeded: `SERVICE_CLEAN 15088 92032`
exceeded the existing 65,536-byte cleanup allowance and the peer exited nonzero.
See [the failed job](https://github.com/jacogr/ragnarok/actions/runs/42487188660/job/128751519252).

A standalone probe reproduces retained memory using only the pinned standard library. Our initial
code also created a new tag space per request, contrary to the documented shared vocabulary
lifecycle. Correcting that usage reduces the retained memory but does not eliminate it: one
process-wide `HttpTags` with 100 freshly parsed and retired messages retains 20,800 bytes on
macOS ARM64. Reusing one message with `reset()` is flat while it lives, but retiring ten such
owners retains 2,080 bytes. Neither observation qualifies complete message cleanup.

The immediate repair temporarily restores the pre-adoption HTTP parsers and their associated
behavior/tests. The independently merged shared socket implementation and MCP polling repair
remain. This is a rollback of #2049, not a new compatibility layer or dependency patch. The
cleanup allowance is unchanged. A repeated-request UI regression requires request-owned memory
to retire after 100 valid requests. Existing RPC, UI, MCP and management suites remain required.

The stock parser adoption remains deferred until the planned Nimony update passes the unchanged
[shared-vocabulary reproducer](nimony-reports-2026-11-08/http-message-retirement.nim), complete
owner cleanup, and the real E2E / Testnet RPC/browser scenario. A renewed adoption must share its
vocabulary as documented and retain stock generic framing and limits, without private runtime
hooks or patches. See [the investigation](nimony-reports-2026-11-08/http-message-retirement.md).

Current upstream compiler/runtime has not been executed for this issue. No upstream issue is
filed here; retest after the planned upgrade before deciding whether submission is needed.
