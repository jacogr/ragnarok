# Bounded state-machine verification

`tlanif` is a separate upstream tool, not a Nimony distribution component. `make model-tools`
builds the exact source revision and SHA-256 archive in `spec/model-tools.json`; `make setup`
includes this prerequisite. Outputs and logs remain under `build/model-tools` and `build/ci`.

The checker is built with Nim from the existing pinned formatter archive, solely as a verification
tool. NIF reader libraries come from the existing pinned Nimony release archive. Both archives
are checksum-verified before extraction, dependency sources remain pristine, and production
compiler pins and PATH stay unchanged. Linux x86-64 and macOS ARM64 use the existing host pins.

Run `build/model-tools/bin/tlanif --help` for upstream options. A source/build identity and binary
checksum validate retained output; changed inputs rebuild instead of trusting an old executable.
`make clean` removes the installation. No global installation or Nimble dependency is required.

Models check bounded abstractions of documented implementation transitions. A passing safety
check alone is insufficient: each model must also kill an intentional guard-removal mutant and
reach its interesting state through a counterexample witness. Parser errors, state-limit exhaustion
and tool failures are never successful counterexamples. This complements native ownership,
cancellation and shutdown tests; it does not establish unbounded correctness or full JAM parity.

Upstream: <https://github.com/Araq/tlanif>, revision
`59e1e5c99b2e1ba3ba5502010f6a9293cc501e08` (MIT; retained in extracted source).
