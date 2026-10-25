# Portable host-history operator bundles and offline commands

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, complete
current Genesis/RawState/TraceStep wire contracts and the seven explicit host/
lifecycle/offender histories selected in the replay contract.

Portable files contain the independently configured complete122-byte Parameters,
trusted Genesis header/map and every consecutive signed TraceStep. Their manifest
freezes configuration, Genesis and each exact step before any native execution.
The public `check-traces --with-state --chain` path reads those actual bounded
files, initializes the configured chain, computes authentic candidate successors
and compares each complete advertised map. It neither obtains expected state from
another client nor seeds a successor from the advertised posterior.

The separate test build selects the already qualified bounded incarnation policy;
production command behavior, default policy and legacy driver profile remain
unchanged. Inputs and emitted resource policy remain byte-stable across jobs.
Wrong Genesis trust, trailing files, recommitted wrong pre/post maps and a later
bad seal retain exact typed failure and accepted-prefix progress with no false
successful root.

Completion requires every positive full-chain command and six exact negative
commands, independent trust/manifest/selection/progress invariants, source
inventory and pinned formatting. Checked macOS/Linux results and exact-head CI
remain distinct. This finite offline qualification does not establish arbitrary
host histories or full JAM/client/network/finality conformance. M1 framing and
complete-state execution retain their separately documented bounds.

Observed: all seven complete command histories (85 transitions) and six exact
negative jobs pass checked ARC/Clang on macOS and Linux. Complete protocol output,
portable manifest and resource-policy hashes match across8,212 frozen source/
native inputs. Every input remains byte-identical after every invocation; all
policy encodings match. All nine independent/tooling tests, source inventory and
pinned formatting (4,799 Nim files plus Rust) pass. Linux image
`ragnarok:db5-rotation-command` is `sha256:4c24326a546f36b9c77ecdefe6367c06d45918b9fc8f48fc6a1e8d784fbe3b0b`.
The preceding replay PR's exact published head passed Compile/Smoke. These are
finite offline/state-transition results, with the broader gaps above retained.
