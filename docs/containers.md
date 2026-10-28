# Container builds

The root [Dockerfile](../Dockerfile) builds the current development proof peer for **Linux amd64**.
It uses the maintained `make build` path: pinned Nimony and Rust, ARC, Clang, release/speed
optimization, ThinLTO, bounds/assertion checks, minified embedded UI and the integration/offload
profiles. This packages the implemented client scope; it does not change the project's release
or protocol-completeness status.

## Build and check

Use Docker with a running Linux container engine and a standalone Git clone. On macOS the
Homebrew Docker CLI needs a runtime such as Docker Desktop or Colima. ARM hosts need amd64
emulation because the pinned compiler has no Linux ARM64 distribution.

```sh
make docker-build          # ragnarok:local, linux/amd64
make check-docker          # Build, then run version/help and checked peer/integration selftests.
docker run --rm --network none ragnarok:local --version
docker run --rm ragnarok:local --help
```

`DOCKER_IMAGE` changes the local image tag. `DOCKER` selects another Docker CLI. Build and smoke
logs remain under `build/ci/docker-{build,smoke}.log`; failure in either phase fails Make.
`DOCKER_PLATFORM` defaults to `linux/amd64`; other architectures currently fail before setup.
No target logs into a registry or publishes images. The fixture-dependent offload selftest stays
in E2E, where its official-vector fixture is prepared; the container smoke checks need no fixtures.

The build context retains only the source Git objects, refs and index needed for the existing
pinned-submodule validation and embedded revision. Local Git config/hooks, dependency checkouts,
host build products and local environment files are excluded. Make fetches pristine dependencies
at the committed gitlinks inside the builder. Linked worktrees and source archives are not build
contexts for this initial image: use a standalone clone with a real `.git` directory. Uncommitted
project edits are built and appear in the binary's dirty revision marker.

## Runtime image

The [multi-stage build](https://docs.docker.com/build/building/multi-stage/) keeps the compilers,
Git metadata and dependency sources in the `builder` stage. The final Ubuntu runtime contains
the peer, maintained crypto/Bandersnatch/QUIC shared libraries, CA certificates and system runtime
libraries. Packaging uses [patchelf](https://github.com/NixOS/patchelf) to replace absolute
build-directory dependencies with library names and a binary-relative runpath into the packaged
library directory. The ThinLTO compiled code and checks remain unchanged. The final-stage
version check catches missing loader dependencies during the build.

The entry point is `ragnarok`; the default passes no arguments and prints help unless
`JAM_FUZZ` activates environment-only conformance. Explicit `--help` always prints help.
It runs as UID/GID **10001:10001**
with working directory `/data`. Bind-mount writable state/configuration directories as needed,
with permissions for that UID; provide TLS certificates/keys at runtime through the existing CLI.
Ports remain explicit CLI choices and Docker port mappings. The image generates no keys or
persistent data during construction.

## Builder and future fuzzing

```sh
docker build --platform linux/amd64 --target builder -t ragnarok:builder .
docker run --rm --entrypoint /bin/bash ragnarok:builder -lc 'make unit SUITE=natural'
```

The builder retains the project, compiler and native build dependencies for later development and
fuzzing targets. Fuzz harnesses, sanitizer/coverage instrumentation, corpora and their CI scheduling
are future work. The release build already retains ThinLTO; a fuzzing target must explicitly
select its required instrumented compiler/linker profile when added.

## CI

The canonical workflow's **Build / Linux & Docker** job packages the Linux archive and then
runs `make check-docker` on the same `ubuntu-latest` runner. Master pushes, `ci:full` PR requests
and manual `build`/`full` requests run this combined job beside **Build / macOS**. The Docker
build keeps its pinned Ubuntu base, pristine dependencies and isolated compiler outputs; host
build products never enter the context. Docker still runs after an earlier archive failure unless
the job is cancelled, and either failure keeps the complete Build gate red.

The `ci:docker` label and manual `docker` scope select just the image check, without native
packaging or macOS. Image selftests run without networking as the non-root runtime user. Only
diagnostics are uploaded; no image is pushed to a registry. To request this scope on a branch:

```sh
gh workflow run ci.yml --ref <branch> -f suite=docker
```
