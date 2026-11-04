# Bounded segment batch serving

Target JAMNP-S aa0e2b8498c0b1bc1725af2903704d701c6577ab CE139/140/148 and GP
fad0ded4a433052397bf7234352a57fe491883f7. Batch messages are concatenated groups,
with canonical natural-prefixed E2 index lists. Preserve group/list order and duplicates;
empty batches/lists are permitted by the sequence grammar. Enforce totals6144 for139/140
and3072 for148, plus independent finite group and encoded-byte resource ceilings.

Callbacks incrementally frame/validate at most4096 input bytes, with no hashing or
canonical ownership. Variable payloads stay on the heap and are charged through actual
native close. Every CPU capture deep-copies variable request storage, so native reset
cannot retire a worker alias. Old fixed methods retain their existing response limits;
139/140 have a32MiB ceiling and148 a16MiB ceiling under existing shared quotas.

CE139/140 selects only private verified137 distributions by exact root/shard. Prepare
one indexed GP tree per distinct source for140, then extract root-first traces without
repeated whole-tree hashing. Precharge aggregate memory/hashes/preimages across all
sources and response copies. CE148 selects the original computed report's segment root,
returns final normalized original exports and their constant-depth GP paths. Neither
framing nor serving grants report inclusion, assurance duty or signing authority.

Completion: canonical/malformed/truncated/oversized variable groups, per-byte parser
boundaries, exact limits and empty/duplicate ordering; indexed proofs match independent
roots and genuine original transfer proofs. Real TLS139/140/148 responses must verify
against independent report roots, including report retirement, reset/close at Done,
foreign-worker exclusion and source mismatch. Retain fixed read/worker/Services tests,
copy-lowering guards, ARC release, build, format and inventory. Acquisition and managed
fallback scheduling follow these actual serving consumers.

Observed local evidence: component and all40 live TLS work/availability cases pass.
The6144-path witness succeeds with exactly two primitive calls for its one stored
source and refuses at one; a two-source batch refuses an aggregate budget of three.
Original65-export paths verify independently; malformed prefixes/counts/extents and
wrong roots/indices refuse complete outputs. Indexed maximum geometry matches the
original trace bytes on an explicitly512KiB thread. ARC stays unchanged over1000
cycles (batch3460880, core4327696, transfer711536). Fixed client/canonical/verification,
worker, Services and foreground node-command consumers pass. Fresh actual copy
lowering rejects NodeService, ApplicationNode, Services and StateProofWorker.
Production build, formatting and inventory pass locally. Acquisition/fallback,
signing/sharing, assurances, audits and full operator activation remain open.
