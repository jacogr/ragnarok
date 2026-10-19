# JAM Ragnarök

An independent [Join-Accumulate Machine (JAM)](https://graypaper.com/) client in **Nim**,
built with **Nimony** against pinned Gray Paper and JAMNP-S specifications.

Ragnarök is a joint effort between the maintainer and AI coding agents, and we are proud of it.
The maintainer sets direction, steers each increment and owns decisions; agents help research,
implement, test and document the work.

## Status

The protocol target is **Gray Paper 0.8.0**. The current implementation includes codecs and
immutable snapshots, state storage foundations, cryptographic adapters, PVM foundations and
authenticated nonblocking QUIC, with optional RPC and telemetry in the development proof peer.
It is not yet a full JAM client or a production validator.

See the [source guide](src/README.md) for modules and proof-peer usage,
[implementation scope](docs/design/scope.md) for coverage and remaining work, and the
[migration audit](spec/graypaper-0.8.0.md) for protocol compatibility and open gates.

## Getting started

Setup supports **Linux x86-64** and **macOS ARM64**. Bootstrap prerequisites are Make,
Python 3.12+ and rustup. Native tools include Clang/C++, CMake, zlib and OpenSSL, plus lld
on Linux. Make installs missing Ubuntu native packages; macOS requires its native development
tools to be available. See the [development guide](docs/development.md) for setup details.

```sh
make check   # Provision dependencies and run complete verification.
make         # Build the development proof peer as build/ragnarok.
```

Make provisions the pinned Nimony compiler and formatter, Rust toolchain and dependency sources.
A global Nim installation is not required. Generated tools, binaries, fixtures and logs stay
under ignored `build/`.

Use `make help` to list targets, `make format` to format Nim and Rust, and `make format-check`
to check formatting. The [development guide](docs/development.md) describes individual check
groups; the [testing guide](docs/testing.md) explains their coverage.

## Q&A

### Is Ragnarök eligible for the JAM Implementer's Prize?

No. We know that our substantive use of AI coding agents breaks
[rule 9 of the JAM Prize](https://jam.web3.foundation/rules), which prohibits substantive
generative AI use. We are building Ragnarök with that understanding.

### Why use coding agents?

We want to explore how a maintainer and coding agents can build a substantial protocol
implementation together. Agents help turn bounded tasks into code, tests and documentation,
while the maintainer directs the work and remains responsible for the result. That makes
readable code, explicit decisions and independent verification central to the project.

### Why Nim when it is not one of the listed JAM languages?

We chose Nim for readable native code, distinct protocol types, explicit ownership and access
to C libraries for low-level primitives. The language choice serves the implementation we want
to build. Nim is absent from the prize's [published language sets](https://jam.web3.foundation/);
rule 3 allows applications for unlisted languages, but that would not address our use of agents.
The original evaluation is preserved in the
[`language-selection` release](https://github.com/jacogr/ragnarok/releases/tag/language-selection).

### Why Nimony?

Nimony is our chosen Nim compiler. Its ARC ownership model and supported contracts fit the
project's immutable snapshots, guarded results and explicit resource lifetimes. We use a pinned
nightly and check the behavior we depend on through positive tests and deliberate runtime and
compilation failures. The [compiler record](docs/nimony-trial.md) documents the migration,
limitations and remaining gates; the [measured comparison](docs/nimony-performance.md) records
the bounded local performance evidence. Nim 2 remains a historical comparison only.

### How do you check the implementation?

We use pinned specifications and published vectors, independent test references, native boundary
and malformed-input tests, ownership checks, compiler rejection tests and live peer scenarios.
`make check` runs the complete verification; Linux CI runs its check groups independently.
Passing those checks is evidence for the implemented scope, not a security audit or proof of
full JAM conformance.

## License

Ragnarök is licensed under either of the following, at your option:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or [Apache license text](https://www.apache.org/licenses/LICENSE-2.0))
- MIT license ([LICENSE-MIT](LICENSE-MIT) or [MIT license text](https://opensource.org/licenses/MIT))

Third-party dependencies and fixtures retain their respective licenses.
