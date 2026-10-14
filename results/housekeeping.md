# Formatting, source ownership and project guidance

Observed locally on 2026-10-14. `odinfmt.json` now matches the requested Exercism
configuration, which links to the Odin examples naming/style conventions. All
project sources were reformatted and the formatter check passes for 82 files.
Markdown's EditorConfig maximum is now 100 columns.

The README opens with the explicit, proud maintainer-led AI collaboration model.
The old codec-only go-ahead sentence is removed; AGENTS.md now requires reporting
and waiting for authorization before any next increment.

Nine top-level Git submodules replace upstream source/archive preparation; their
recorded nested modules also initialize at pinned revisions. All original source
commits remain unchanged. Twenty-one identical copied upstream vector/license
files were checked against their submodule originals and removed from the parent
repository. Test runners read upstream fixtures directly; project-owned reduced
JAM cases, boundary fixtures and RFC transcription remain local. Cargo.lock and
toolchain checksums retain their package/binary roles.

The dependency guide is [docs/dependencies.md](../docs/dependencies.md). Linux CI
initializes submodules using `tools/setup_submodules.py`, which limits the large
JAM vector checkout to codec/Safrole data. A fresh temporary parent repository
successfully initialized this partial/sparse checkout and repeated initialization;
required fixtures were present and the multi-gigabyte trace folder was absent.
LSQUIC's accidentally unstaged gitlink was restored at its original pinned commit.
No parent commit or push was made.

Executed checks:

```sh
python3 tools/setup_submodules.py
python3 tools/format.py --check
cargo fmt --manifest-path native/bandersnatch/Cargo.toml -- --check
python3 interoperability/test_codec.py
python3 interoperability/test_crypto.py --fetch
python3 interoperability/test_bandersnatch.py --fetch
python3 interoperability/test_quic.py --fetch
python3 interoperability/test_quic_soak_harness.py
git diff --check
```

All passed locally: full codec conformance/native/type checks, four ordinary
crypto suites, four Bandersnatch suites and integrity checks, the 64-case QUIC
matrix/native I/O tests, and five soak-harness regressions. The source/init helper
refuses unexpected revisions and local edits instead of resetting dependency
work. This housekeeping round did not rerun the 160-session lifecycle soak;
its transport behavior/workload is unchanged. The updated Linux workflow still
awaits a pushed run.
