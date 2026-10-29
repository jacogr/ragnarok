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

The upstream target manager configures the ordinary executable through environment
variables. No Fuzz arguments, external policy files or shell launcher are needed:

```sh
JAM_FUZZ=1 \
JAM_FUZZ_SPEC=fuzz \
JAM_FUZZ_DATA_PATH=/tmp/ragnarok-fuzz/data \
JAM_FUZZ_SOCK_PATH=/tmp/ragnarok-fuzz/target.sock \
JAM_FUZZ_LOG_LEVEL=info \
./build/ragnarok
```

`JAM_FUZZ` selects conformance mode. `JAM_FUZZ_SPEC` selects `tiny`, `full` or the
experimental `fuzz` preset. The binary creates the selected runtime directories,
uses its built-in bounded host policy and listens on `JAM_FUZZ_SOCK_PATH`.
`JAM_FUZZ_LOG_LEVEL` is optional. `--version` remains available for launcher
introspection. Missing required configuration and extra Fuzz arguments fail locally.

The immutable chain catalog is `src/chain/presets.nim`; native host defaults live
in `src/app/fuzz/policy.nim`. Chain-dependent policy fields come from that catalog;
resource ceilings remain explicit. Fuzz uses the approved D900 interpretation.
Legacy explicit-policy commands remain for existing internal regression callers.

The workflow-level `JAM_FUZZ_TARGET_SOCK` is consumed by upstream tooling, which
passes the target's endpoint as `JAM_FUZZ_SOCK_PATH`. Engine generation controls
such as `JAM_FUZZ_SEED` belong to the external engine, not the target client.

## Container defaults

```sh
make docker-build-jam-fuzz
mkdir -p build/jam-network-runtime
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
  -v "$PWD/build/jam-network-runtime:/jam" \
  -e JAM_FUZZ=1 -e JAM_FUZZ_SPEC=fuzz -e JAM_FUZZ_DATA_PATH=/jam \
  -e JAM_FUZZ_SOCK_PATH=/jam/target.sock -e JAM_FUZZ_LOG_LEVEL=info \
  ragnarok:local-jam-fuzz
```

The image inherits the ordinary `/usr/local/bin/ragnarok` entry point. It needs no
custom command arguments or policy assets. The ordinary image remains the default
build product, and its normal default help argument also permits environment-selected
Fuzz startup. The preset image only adjusts default user/arguments for upstream
rootless launch. Its tag follows `${DOCKER_IMAGE}-jam-fuzz`; linked worktrees need
a standalone build context.

The binary creates selected runtime directories with0700 and tightens existing
runtime-owned directories, including upstream's0777 mount. Rootful Docker uses
the host UID supplied by the launcher. For rootless Docker, omit `--user` so
container root maps to the host owner. Some macOS Docker setups translate
bind-mount ownership; use a Linux-owned volume there.

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
