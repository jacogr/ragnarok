# Maintained LSQUIC fork qualification

The native QUIC adapter moves from `fd0d75c6584eb4c20dfa8b4b865bfe3daf5a2e52`
to `0c9c66903b70ac25852d70d54672005aafb1a446`. The candidate is an eleven-commit
descendant. It changes path-probe amplification accounting, ACK history merging,
early IETF close encryption and the idle PING policy. The adapter continues to
select IETF QUIC v1. The BoringSSL and nested QPACK/HPACK gitlinks are unchanged.

The old fork armed PINGs with a nonzero interval even when every application
stream had closed. The new fork defaults that behavior off. The adapter enables
it whenever its effective interval is nonzero, including the existing client
default and the recovery profiles' one-second probes. The server default with
a zero interval stays disabled. Idle timeouts are unchanged.

The pristine-source build on master needs no LSQUIC patch. The separate JAMNP-S
stream-reset patch applies cleanly to the candidate and remains necessary for
that stack's public reset adapter. The candidate does not provide its public
`lsquic_stream_reset` symbol. A successful patch dry run is source compatibility
evidence. Linked reset qualification belongs to the integration of the two
branches.

## Qualification

The three `test_build_quic.py` tests passed locally. They cover incompatible
compiler cache reset, compatible cache reuse and missing compiler refusal.
The Release bridge built on macOS ARM64 with the pinned dependencies in an
isolated build directory. The candidate's Debug CTest binaries `ping_alarm`,
`trechist`, `sess_resume`, and `stream` passed. The timer test checks disabled
no-stream PINGs, the explicit opt-in, the last-stream-close case and a zero
interval.

The repository transport E2E group passed on macOS ARM64. Its idle regression
authenticated without opening a stream, kept both peers live for 3.01 seconds,
then killed the server. The idle client retired after 1.28 seconds. The
transport group also covered mutual authentication and rejection, CE143
and digest service, mesh and peer-death recovery, admission, teardown soak,
and bounded proof offload. The fork's Debug `path` and `conn_close_ietf`
tests passed.

The candidate was tested against master `7048e169190aa6b378d0f713712892f10722f12a`
using Apple Clang 21.0.0. Build and test receipts are under the isolated
worktree's `build/lsquic-upgrade/` and `build/tests/e2e/`. Linux CI
qualification remains pending.
