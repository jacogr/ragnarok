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

The approved build patch records the MTU size of each stored PATH_CHALLENGE
nonce. A response to a smaller challenge validates reachability and leaves a
different outstanding MTU-sized probe and its retry alarm pending. The
regression returns the smaller nonce, then the padded nonce, then the smaller
nonce again. The unpatched candidate fails the first MTU assertion.

The manifest binds the patch digest and the input and output source digests
to the candidate revision. The build stages a fresh copy under
`build/native/lsquic-source` and verifies both patches there. The unchanged stream-reset patch from
master is rebound to the candidate using its input and output source digests.

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

The original upgrade qualification used master `7048e169190aa6b378d0f713712892f10722f12a`
using Apple Clang 21.0.0. Build and test receipts are under the isolated
worktree's `build/lsquic-upgrade/` and `build/tests/e2e/`. Linux CI
qualification remains pending.

The build-patched Release bridge and the three build-tool tests passed on
macOS ARM64. The patched Debug `path`, `ping_alarm`, and `conn_close_ietf`
tests passed. The `path` test failed on the unpatched candidate with the new
regression enabled and passed with the nonce fix.

With the nonce-patched Release bridge, the idle regression survived 3.00
seconds with zero application streams and retired 1.31 seconds after peer
death. This run reused the earlier application binary linked to the rebuilt
bridge.

The combined qualification used JAMNP-S stack tip
`2f92c5bb26a21364b62c96363752896d5cdc87b5` in a separate worktree. It staged
both patches with hashes calculated against the new LSQUIC pin. The stack's
unchanged reset patch linked its public API into the Release bridge.
`application_download_loop` passed, including actual peer observation of a
reset on an unsolicited stream while a download worker held its lease.
ARC occupied memory held at 157,568 bytes across 1,000 cycles. The combined
Debug `path`, `ping_alarm`, and `conn_close_ietf` tests passed too.

The LSQUIC CMake cache is keyed by the pinned sources and ordered patch
manifest. In one macOS build root, Release builds switched from reset plus
nonce to nonce only and back. Symbol inspection found `lsquic_stream_reset`
in the static archive and linked bridge only for the two-patch configuration.
Returning to that configuration reused its cache. The four build-tool tests
passed, including cache selection across pin and patch changes.

After the JAMNP-S stack landed, the upgrade was merged with master at
`3bf3b819fcb3549a9c9a10661ae1e936a2953962`. The resulting patch manifest,
build driver, and native bridge inputs matched the combined qualification
byte for byte. All six build-tool tests passed, including the landed staging
and digest rejection tests updated to exercise both patches.
