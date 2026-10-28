# Binary CI archives

The **Build / Linux & Docker** and **Build / macOS** jobs compile the production peer with the
same pinned Nimony, ARC, Clang, release/speed optimization, ThinLTO and runtime checks used by
E2E. The Linux runner uses `ubuntu-latest` and performs native archive packaging followed by an
independent Docker build/smoke check; macOS retains its native ARM64 host. Docker still compiles
inside its pinned image and excludes host build outputs. The **Build** aggregate requires both
jobs to pass, including both Linux deliverables.

Master pushes, `ci:full` requests and manual `build`/`full` requests run the complete Build group.
The `ci:docker` label and manual `docker` scope run only the Docker check on `ubuntu-latest`,
without either native archive build. Docker still runs after an earlier Linux packaging failure
unless cancelled; the original failure remains authoritative. Separate native/Docker diagnostics
and the existing downloadable archive names are retained. These jobs publish no GitHub Releases
or container images.

Download the `ragnarok-linux-amd64` or `ragnarok-macos-arm64` artifact from the workflow run.
The artifact contains a `.tar.gz` and its `.sha256` checksum. Verify the checksum with
`sha256sum -c <archive>.sha256` on Linux or `shasum -a 256 -c <archive>.sha256` on macOS,
then unpack the archive and run `bin/ragnarok --version` or `bin/ragnarok --help`.
Keep `bin/` and `lib/ragnarok/` together: the peer uses relative loader paths to its bundled
crypto, Bandersnatch and QUIC libraries. The manifest records the revision, compiler pin,
platform, LTO mode and payload checksums; both project licenses are included.

The Linux archive is built on GitHub's `ubuntu-latest` image and requires compatible system
glibc, libstdc++, libgcc and zlib runtimes plus CA certificates. Its minimum runtime baseline
therefore follows the selected runner image; the Docker runtime remains separately pinned. The macOS archive targets Apple Silicon on
macOS 15 or later and is ad-hoc signed for smoke testing, not Developer ID signed or notarized.
Windows, Linux ARM64 and Intel macOS archives are not offered: they lack the complete pinned
compiler/native-build support required by this path. This packages the implemented development
peer scope and does not change the project's protocol/release-readiness claims.

Locally, `make package-binary` provisions dependencies, builds the peer and writes the archive
and checksum under `build/dist/`. On Linux, Make also provisions `patchelf`. Packaging rewrites
only copied binaries, validates their dependency closure, unpacks the candidate archive into a
new directory, and runs `--version`, `--help`, `--selftest` and `--integration-selftest` there.
A failed loader check or selftest prevents publication and removes stale output archives.
Diagnostics remain in `build/ci/binary-package.log`.
