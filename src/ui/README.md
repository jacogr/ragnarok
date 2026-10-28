# Browser UI and static server

[Source guide](../README.md) · [UI contract](../../spec/ui.md) ·
[Browser prototype](../../spec/ui-browser.md)

This folder contains the Nimony browser prototype and the native server that embeds its assets.

| Module | Contents |
| --- | --- |
| [`client.nim`](client.nim) | Browser DOM/presentation code, including client-info queries |
| [`rpc.nim`](rpc.nim) | Browser WebSocket JSON-RPC calls and independently routed subscriptions |
| [`server.nim`](server.nim) | Bounded loopback HTTP server for immutable embedded gzip assets or an explicit development directory |

Append `--with-ui` to a supported proof-peer invocation to serve the browser at
`http://127.0.0.1:8888/`; `--ui-port NUMBER` changes the port. This also enables
[WebSocket RPC](../rpc/README.md). The prototype displays `ragnarok_clientInfo`; the browser's
RPC URL is editable for nondefault endpoints.

Make compiles the browser with the pinned Nimony JS backend and gzips the static assets into an
embedded manifest. CI minifies JS/CSS with pinned native esbuild; local builds enable the same
step with `UI_MINIFY=1`. The HTTP server requires gzip acceptance and has no uncompressed fallback.
For development, append `--ui-dev-dir build/ui` alongside `--with-ui` and rebuild with
`make ui-assets`.

[Application services](../app/README.md) own both listeners and drive them from the peer
dispatcher. The [UI contract](../../spec/ui.md) and
[browser contract](../../spec/ui-browser.md) describe request/resource limits, asset provenance,
transport behavior and native/real-browser verification.
