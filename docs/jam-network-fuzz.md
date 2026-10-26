# JAM network fuzz target

The experimental `fuzz` preset follows
[davxy/jam-conformance issue215](https://github.com/davxy/jam-conformance/issues/215):
85 cores,60-slot epochs,255 initial validators, and variable populations down to six.
All nine overrides are explicit; every other Appendix B value remains Full. This
imports blocks over the fuzz-v1 Unix socket. Use [Tiny devnet](tiny-devnet.md) for
six actual QUIC validators producing and consuming blocks on a slot clock.

## Verify locally

```sh
make check-jam-network
```

Make provisions pinned dependencies and builds the checked native target. The runner
calculates signed blocks and complete expected maps before starting native execution.
It checks67 imports across17 sessions: ordinary/skipped epoch transitions,
delayed255-to252/6 activation, nonempty guarantees,171/172-vote availability siblings,
storage/yield, panic rollback, checkpoint retention and exact/strict D900 expiry. Every observed map must match;
invalid imports must preserve the prior map and permit the genuine next import.
Reconnect isolation and SIGTERM socket cleanup are required.

`build/tests/jam-network/` retains native build/run logs, the independent plan,
`results.json`, `summary.md` and target diagnostics. **Fuzz / JAM Network** runs this
readiness workload separately from **Fuzz / JAM** and **E2E / Testnet**. Request the
Fuzz group with the existing `ci:fuzz` PR label.

## Run the normal binary

```sh
build/ragnarok --fuzz --fuzz-policy config/jam-fuzz-policy.conf \
  --fuzz-spec fuzz --fuzz-data /tmp/ragnarok-fuzz/data \
  --fuzz-socket /tmp/ragnarok-fuzz/target.sock \
  --fuzz-log-level info --fuzz-writes 1000 --fuzz-write-bytes 4194304
```

All mode selection, argument validation, directory creation, policy loading and
socket cleanup happen in `ragnarok`. The replay runs this executable directly.
Flags override the optional upstream `JAM_FUZZ_SPEC`, `JAM_FUZZ_DATA_PATH`,
`JAM_FUZZ_SOCK_PATH` and `JAM_FUZZ_LOG_LEVEL` values. No environment variables are
needed when the flags supply the configuration. An ambient `JAM_FUZZ` variable
does not change ordinary commands such as `--version`.

The immutable Tiny/Full/Fuzz catalog is `src/chain/presets.nim`. Fuzz uses explicit
D900. Policy copies of consensus limits must match that catalog; local resource
ceilings are configured separately. `--fuzz-parameters FILE` selects an explicit
custom parameter tuple for existing Tiny/Full host profiles. The positional
`serve-fuzz` and `serve-fuzz-preset` commands remain compatible.

## Container defaults

```sh
make docker-build-jam-fuzz
mkdir -p build/jam-network-runtime
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
  -v "$PWD/build/jam-network-runtime:/jam" \
  -e JAM_FUZZ_SPEC=fuzz -e JAM_FUZZ_DATA_PATH=/jam \
  -e JAM_FUZZ_SOCK_PATH=/jam/target.sock \
  -e JAM_FUZZ_LOG_LEVEL=info ragnarok:local-jam-fuzz
```

The image inherits the ordinary `/usr/local/bin/ragnarok` entry point. It only
bundles `config/jam-fuzz-policy.conf` and supplies default `--fuzz` arguments.
Supplying arguments to `docker run` replaces these defaults exactly as it does for
the normal image; there is no Fuzz shell launcher or separate executable. The
ordinary image remains the default build product. The tag follows
`${DOCKER_IMAGE}-jam-fuzz`. Linked worktrees require a standalone build context.

The binary creates missing selected runtime directories with0700 and tightens
existing runtime-owned directories, including upstream's0777 mount. Rootful Docker
uses the host UID supplied by the upstream launcher. For rootless Docker, omit
`--user` so container root maps to the host owner. Some macOS Docker setups
translate bind-mount ownership; use a Linux-owned volume in those environments.

## Live campaign prerequisite

A ready target is not a generated campaign pass. Results retain
`engine_validation: pending`. No random replacement engine, empty campaign or
successful minifuzz exit can satisfy a live campaign verdict.

A compatible GP0.8 `polkajam-fuzz` engine is still required. At the pinned upstream
revision `acd4b2da310ff25226c4d41b918712578483fd2c`, both `scripts/target.py`
and `scripts/fuzz-workflow.py` restrict `--spec` to Tiny/Full. Issue215's launcher
support must be available before the standard network workflow can select Fuzz.
No upstream files or dependency pins are patched here.

The bundled host policy is finite:16MiB wire messages,4MiB complete state/write
values,1000 writes per publication,601 retained ancestry facts and16MiB retained
header evidence. Other guest/service bounds are explicit in the policy. It covers
the independently declared readiness workload; a generated campaign may expose
additional local capacity requirements. Local refusals must remain visible and
cannot be reported as protocol-invalid blocks or successful campaign steps.

The pinned Initialize message carries at most24 hash/slot ancestry records. The
600-slot lookup age does not increase that wire limit or supply missing child-header
roots. GP checks remain enabled; missing evidence closes locally with diagnostics.
