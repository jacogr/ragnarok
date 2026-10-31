# Pinned upstream sources

Git submodules under `vendor/` pin exact upstream commits. The parent repository maintains narrow
bridges and pin metadata rather than copied dependency source trees. Initialize them with:

```sh
python3 tools/setup_submodules.py
```

| Submodule | Purpose |
| --- | --- |
| `vendor/lsquic` | QUIC transport, including its recorded QPACK/HPACK children |
| `vendor/boringssl` | QUIC/TLS |
| `vendor/ark-vrf` | Draft-29 release-reference ark-vrf 0.2.2 backend |
| `vendor/bandersnatch-vrf-spec` | Published historical suite vectors and SRS |
| `vendor/graypaper` | [Pinned Gray Paper specification and current qualification](../spec/graypaper-credential-encoding.md) |
| `vendor/jam-np` | JAMNP-S networking specification |
| `vendor/jamtestvectors` | Pinned `jam-conformance/jam-test-vectors` gp-next codec, STF and trace fixtures |
| `vendor/jam-conformance` | Pinned `jam-conformance/jam-fuzzing` protocol and campaign tooling |
| `vendor/wycheproof` | Independent adversarial Ed25519 corpus and license |

Setup checks recorded gitlinks and refuses local upstream edits or unexpected revisions. It does
not run upstream install scripts. JAM vectors use a sparse checkout of `codec` and `stf/safrole`;
unrelated large trace sets are not materialized. Nested native dependencies retain their parents'
recorded revisions.

The active compiler/formatter archives are pinned in `spec/toolchain.json`; older compiler fields
in protocol/fixture pins record historical test provenance, not a second supported target.
JSON pins under `spec/` retain source identities, interpretation and vector/SRS hashes. Cargo.lock
pins transitive registry versions/checksums; builds use locked offline dependencies after explicit
provisioning. `--fetch` initializes required submodules and permits missing locked Cargo packages
to be downloaded. No test runner silently advances gitlinks or patches upstream code.

Project bridges live under `native/`: C handles primitive/transport integration, Rust handles
Bandersnatch and ordinary crypto primitives, and Nim under `src/` owns JAM codec/domain/identity policy. Upstream licenses
remain in the source submodules; project-authored boundary and derived fixtures stay under `vectors/`.
Derived JAM fixtures are checked against their complete original upstream cases.

Generated CMake/Rust output, temporary fixture keys and logs live under ignored `build/`. For a
deliberate dependency upgrade, update the gitlink together with its pins/hashes and run affected
verification. Functional vector agreement does not replace dependency/security audit.
