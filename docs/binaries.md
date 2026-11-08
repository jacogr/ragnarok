# Binary CI archives

The **Build / Linux x86-64**, **Build / Linux ARM64** and **Build / macOS ARM64** jobs compile
the production peer with pinned Nimony, ARC, Clang, release/speed optimization, ThinLTO and runtime
checks. Each archive is packaged and smoke-tested on its native host. The independent
**Build / Docker** job compiles inside its pinned image and exercises the container entry points.

Master pushes, `ci:full` requests and manual `build`/`full` requests run all four builds.
The `ci:docker` label and manual `docker` scope select the Docker job. These are CI artifacts;
release publication remains a separate maintainer operation.

Download the `ragnarok-linux-amd64`, `ragnarok-linux-arm64` or `ragnarok-macos-arm64` artifact
(with its run-attempt suffix) from the workflow run. Each native artifact contains a `.tar.gz`
and its `.sha256` checksum. Verify it with `sha256sum -c <archive>.sha256` on Linux or
`shasum -a 256 -c <archive>.sha256` on macOS, then unpack the archive and run
`bin/ragnarok --version` or `bin/ragnarok --help`.
Keep `bin/` and `lib/ragnarok/` together for the peer's relative library paths. The manifest
records the revision, compiler pin, platform, LTO mode and payload checksums; both project
licenses are included.

Linux archives use `ubuntu-26.04` for x86-64 and `ubuntu-26.04-arm` for ARM64. They require
compatible system glibc, libstdc++, libgcc and zlib runtimes plus CA certificates. Their minimum
runtime baseline follows those runner images. The macOS archive targets Apple Silicon on
macOS 15 or later and is ad-hoc signed for smoke testing. Windows and Intel macOS packaging
remain outside the supported platform set. The archives package the implemented development
peer scope described by the project's current feature contracts.

Locally, `make package-binary` provisions dependencies, builds the peer and writes the archive
and checksum under `build/dist/`. On Linux, Make also provisions `patchelf`. Packaging rewrites
only copied binaries, validates their dependency closure, unpacks the candidate archive into a
new directory, and runs `--version`, `--help`, `--selftest` and `--integration-selftest` there.
A failed loader check or selftest prevents publication and removes stale output archives.
Diagnostics remain in `build/ci/binary-package.log`.
