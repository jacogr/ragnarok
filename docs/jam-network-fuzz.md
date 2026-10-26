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

## Container entry point

```sh
make docker-build-jam-fuzz
mkdir -p build/jam-network-runtime
chmod 700 build/jam-network-runtime
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
  -v "$PWD/build/jam-network-runtime:/jam" \
  -e JAM_FUZZ=1 -e JAM_FUZZ_SPEC=fuzz \
  -e JAM_FUZZ_DATA_PATH=/jam -e JAM_FUZZ_SOCK_PATH=/jam/target.sock \
  -e JAM_FUZZ_LOG_LEVEL=info ragnarok:local-jam-fuzz
```

The Make image tag is `${DOCKER_IMAGE}-jam-fuzz`; its default follows the normal
Docker build configuration. As with the ordinary Docker target, linked worktrees
need a standalone clone as build context. Use a matching writable host UID for
rootful Docker; the standard upstream launcher supplies it. Directories must be
owned by the runtime user; the entry point tightens these explicitly selected
directories to0700, including the upstream launcher's0777 shared runtime directory.
For rootless Docker, omit the explicit `--user`: container root maps to the host
user, matching the standard upstream launcher.

Some macOS Docker setups translate bind-mount ownership. For those setups, initialize
a Linux-owned volume and use `-v ragnarok-jam-fuzz:/jam` in the command above:

```sh
docker volume create ragnarok-jam-fuzz
docker run --rm --platform linux/amd64 --user 0:0 \
  -v ragnarok-jam-fuzz:/jam --entrypoint sh ragnarok:local-jam-fuzz \
  -c "chown $(id -u):$(id -g) /jam && chmod 700 /jam"
```

The dedicated image accepts standard environment variables without command-line
arguments. It selects the immutable canonical catalog in `src/chain/presets.nim` and bundles
`config/jam-fuzz-policy.conf`. Tiny, Full and Fuzz Appendix B scalars are defined in
that catalog; the Fuzz expunge period explicitly uses D900. Existing Tiny/Full/custom
expiry semantics remain unchanged. Policy copies of consensus limits must match the
selected catalog; local resource ceilings are configured separately.
Only `fuzz` is supported by this dedicated image. The ordinary image remains the
default build product and its entry point is unchanged. The native binary continues
to support explicit Tiny/Full `serve-fuzz` configurations.

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
