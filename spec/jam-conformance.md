# Pinned JAM conformance tooling

The maintainer selected the latest main revision of
[jam-conformance/jam-fuzzing](https://github.com/jam-conformance/jam-fuzzing) on2026-10-30:
3a488be18fe7b94aa1d35bd0d6f8981ec5bbefae. The recorded gitlink and
jam-conformance-pins.json bind that immutable revision, the fuzzer-v1 schema,
protocol documentation, minifuzz self-test and CLI workflow/target management
scripts. Selected upstream file SHA-256 identities are checked by Python discovery.

The canonical repository is now `jam-conformance/jam-fuzzing` (formerly
`davxy/jam-conformance`). The local `vendor/jam-conformance` path is retained. This is the actively maintained upstream,
rather than the older w3f mirror.
The selected workflow supports a prebuilt polkajam-fuzz through
POLKAJAM_FUZZ_BIN; access to its source workspace is not a prerequisite.
The live campaign engine is nevertheless a separate artifact and is not included
in this source pin. The pin adds fixed GP0.8.0 forks/no-forks examples alongside GP0.7.0/0.7.2
historical sessions. Minifuzz, fuzzer-v1 schema and selected CLI scripts are byte-identical
to the previous pin. The obsolete upstream `.gitmodules`, crypto and PVM trace trees
were removed; no nested repository is initialized. Pinning the tooling does not
establish GP0.8 or current-gp-next campaign success (see [wire qualification](jam-fuzzer-wire.md)).
Upstream requires a matching jam-types-py release when decoding published sessions;
we do not replay these sessions through mismatched Python types or silently advance
the separately pinned live-driver dependencies.

Standard make sources/setup/check-python provisioning initializes the new
submodule through tools/setup_submodules.py. A shallow blob-filtered checkout
materializes root documents, fuzz-proto and scripts. It leaves multi-gigabyte
historical fuzz-reports absent and does not initialize upstream's independent
nested test-vectors repository. This preserves Ragnarök's existing vector pin.
No upstream installer, workflow or target binary executes during source setup.

Setup selects the recorded index gitlink rather than following main, preserves
a warm focused checkout, supports deinitialization/reinitialization and refuses
local source edits before moving any selected source. Local Git regression
fixtures cover these properties without using the network. Exact checkout,
source hashes, configured URL and indexed pin are also checked directly.
For focused provisioning, run:

    python3 tools/setup_submodules.py vendor/jam-conformance
    PYTHONPATH=tools:tests python3 -m unittest test_jam_conformance_pin test_setup_submodules

This increment establishes the reproducible input for the planned JAM campaign
target/CI integration. It does not add a campaign pass or a placeholder Fuzz job.
This tooling layer changes no Gray Paper, VRF or historical fixture semantics.
The separate lower stack layer upgrades protocol vectors; see [its qualification](vector-gp539-upgrade.md).
