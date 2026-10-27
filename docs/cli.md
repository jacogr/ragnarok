# Command line

Run `ragnarok --help` for grouped shared settings and the command list. Use
`ragnarok server --help` or `ragnarok help server` for the networking inputs and
service options accepted by that command. `ragnarok tiny-devnet --help` lists its
subcommands. No arguments show the overview, except when the public `JAM_FUZZ`
environment explicitly activates conformance. Explicit help never starts services.

Every command value has a named flag. Positional forms are rejected, and flags may
be interleaved after the command. Networking settings use `--net-*`; downloads,
traces, development validators and conformance use their respective `--download-*`,
`--trace-*`, `--devnet-*` and `--fuzz-*` prefixes. `--net-cert` and `--net-key` are the
local TLS certificate/private key; `--net-peer-key` selects the pinned peer identity.
`--net-local-key` selects the separate mesh identity. Keep these key roles distinct.

```sh
ragnarok server --net-port 4000 \
  --net-cert node.cert.pem --net-key node.key.pem --net-peer-key - \
  --net-alpn "$configured_alpn" \
  --with-ui --ui-port 9000 \
  --with-state --chain chain.json

ragnarok download-current --net-port 4001 \
  --net-cert node.cert.pem --net-key node.key.pem --net-peer-key peer.pub \
  --net-alpn "$configured_alpn" --net-peer 4002:another-peer.pub \
  --download-policy current-policy.conf --download-blocks 2 \
  --with-state --chain chain.json

ragnarok check-traces --trace-policy current-policy.conf --trace-genesis genesis.bin \
  --trace-file step-0.bin --trace-file step-1.bin \
  --with-state --chain chain.json

ragnarok tiny-devnet node --devnet-dir data --devnet-index 0 \
  --devnet-base-port 4000 --devnet-start-unix-ms "$start_ms" \
  --devnet-stop-slot 4 --devnet-policy current-policy.conf
```

`--with-ui`, `--with-rpc`, `--with-management`, `--with-telemetry` and `--with-state`
appear before their settings in help. Configuring an endpoint, path or port does
not enable its service. UI also enables RPC. Help shows required fields and
resolved defaults; defaults are defined in `src/app/cli_defaults.nim`, with the
shared diagnostic threshold owned by `src/lib/logging.nim`. Conformance has its own
write budgets rather than borrowing execution defaults.

Repeat `--trace-file FILE` in execution order, `--download-ancestor FILE` newest
first, and `--net-peer PORT:KEY_FILE` for additional peers. Other flags are unique.
`--name=value` is accepted for value options. Required files, identities, protocols
and policies have no inferred substitutes. Unknown flags, missing values, wrong-command flags and mixed bare
values are refused before networking or file IO.

Only the advertised canonical option names are accepted; legacy aliases and
positional command forms are rejected. Internal component fixtures receive normalized
command values through `parseCanonicalOptions`; process input must go through the
strict `parseOptions` boundary.

Conformance can still be launched with only the official environment variables:

```sh
JAM_FUZZ=1 JAM_FUZZ_SPEC=tiny JAM_FUZZ_DATA_PATH=/tmp/fuzz-data \
  JAM_FUZZ_SOCK_PATH=/tmp/fuzz.sock ragnarok

ragnarok fuzz --fuzz-spec tiny --fuzz-data-path /tmp/fuzz-data \
  --fuzz-sock-path /tmp/fuzz.sock --fuzz-log-level debug
```

The `fuzz` command activates the same built-in policy without requiring `JAM_FUZZ`
or policy files. `--fuzz-spec`, `--fuzz-data-path`, `--fuzz-sock-path` and
`--fuzz-log-level` override `JAM_FUZZ_SPEC`, `JAM_FUZZ_DATA_PATH`,
`JAM_FUZZ_SOCK_PATH` and `JAM_FUZZ_LOG_LEVEL`, respectively. Omitted flags keep the
captured environment value. Spec, data path and socket path must be supplied by
one of these sources; logging otherwise uses the ordinary default. A general
`--log-level` filter takes precedence over the conformance logging threshold.
The explicit-policy `serve-fuzz` and `serve-fuzz-preset` commands accept these
same environment overrides. Help identifies every mapping.
