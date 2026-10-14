# Pinned upstream sources

Git submodule entries under `vendor/` pin the exact upstream commits. The parent
repository stores Git references, not copies of their source trees or published
fixture files. Existing revisions are unchanged.

| Submodule | Purpose |
| --- | --- |
| `vendor/lsquic` | QUIC transport; recursively includes its pinned QPACK/HPACK children |
| `vendor/boringssl` | Shared TLS and Nim Blake2b/Ed25519 backend |
| `vendor/xkcp` | Nim legacy Keccak backend; recursively includes its pinned XKCBuild tooling |
| `vendor/ark-vrf` | Original JAM Bandersnatch Rust backend |
| `vendor/bandersnatch-vrf-spec` | Historical specification, published vectors and public SRS |
| `vendor/graypaper` | GP v0.7.1 source specification |
| `vendor/jam-np` | Pinned JAMNP-S source specification |
| `vendor/jamtestvectors` | Official codec and Safrole fixtures |
| `vendor/wycheproof` | Independent Ed25519 adversarial corpus and its license |

After cloning, run:

```sh
python3 tools/setup_submodules.py
```

The command initializes recorded commits and nested dependencies without executing
upstream scripts. It refuses local source edits or unexpected checkout revisions.
JAM vectors use a partial clone and sparse checkout of `codec` and `stf/safrole`;
several gigabytes of unrelated traces are not materialized. Ordinary
`git submodule update --init --recursive` also works, but creates a full checkout.
Linux CI uses the focused setup command after checking out the parent repository.

Existing JSON pin files retain protocol/toolchain interpretation and content
hashes; the runners cross-check their source metadata against each Git checkout.
The source must remain clean and at its recorded revision. Bandersnatch also
retains complete source-tree and SRS hash checks. No dependency source patches
are introduced by this change. `--fetch` initializes missing required submodules;
Bandersnatch additionally downloads missing locked Cargo packages. Builds then
use the initialized local sources.

Copied upstream codec, Wycheproof and published Bandersnatch vectors/licenses
have been removed from the parent repository and are read directly from their
submodules. Project-authored boundary fixtures, RFC vector transcription and
small derived JAM fixtures remain local. The derived fixtures are still checked
against complete original cases in the official-vector submodule.

Cargo.lock pins registry package versions/checksums; compiler and binary-download
checksums pin toolchains. Those mechanisms remain appropriate for packages and
executables and are not replaced with one submodule per transitive crate.

Build products live under ignored `build/`. BoringSSL and LSQUIC CMake builds
now use `build/native/boringssl` and `build/native/lsquic`; the Rust crate references
its source/SRS submodules directly. Prior ignored archive caches are no longer
consulted. They are left in place so any old diagnostics remain recoverable.

For a deliberate upgrade, update the submodule checkout and its metadata/hashes,
run the affected checks, and stage the changed gitlink together with that metadata.
A clean source edit is never silently discarded or rewritten by a test runner.
