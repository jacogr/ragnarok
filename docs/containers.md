# Container builds

The root [Dockerfile](../Dockerfile) builds the current development proof peer for **Linux amd64**.
It uses the maintained `make build` path: pinned Nimony and Rust, ARC, Clang, release/speed
optimization, full LTO, bounds/assertion checks, minified embedded UI and the integration/offload
profiles. This packages the implemented client scope; it does not change the project's release
or protocol-completeness status.

## Build and check

Use Docker with a running Linux container engine and a standalone Git clone. On macOS the
Homebrew Docker CLI needs a runtime such as Docker Desktop or Colima. ARM hosts need amd64
emulation because the pinned compiler has no Linux ARM64 distribution.

```sh
make docker-build          # ragnarok:local, linux/amd64
make check-docker          # Build, then run version/help and checked peer selftests.
docker run --rm --network none ragnarok:local --version
docker run --rm ragnarok:local --help
```

`DOCKER_IMAGE` changes the local image tag. `DOCKER` selects another Docker CLI. Build and smoke
logs remain under `build/ci/docker-{build,smoke}.log`; failure in either phase fails Make.
`DOCKER_PLATFORM` defaults to `linux/amd64`; other architectures currently fail before setup.
No target logs into a registry or publishes images.

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
library directory. The full-LTO compiled code and checks remain unchanged. The final-stage
version check catches missing loader dependencies during the build.

The entry point is `ragnarok`; the default command prints help. It runs as UID/GID **10001:10001**
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
are future work. The release build already retains full LTO; a fuzzing target must explicitly
select its required instrumented compiler/linker profile when added.

## CI

The canonical workflow's **Docker image** job runs `make check-docker` independently on master
pushes and requested `unit`/`full` runs (`ci:unit` or `ci:full` on PRs). It builds a local image and
runs its selftests without networking under the runtime user. Only diagnostic logs are uploaded;
images are not pushed to any registry. To request just this job on a branch:

```sh
gh workflow run ci.yml --ref <branch> -f suite=docker
```
