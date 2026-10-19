# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned corpus orchestration; expected results remain in independent test oracles.

Exposes run_bandersnatch and run_crypto to execute primitive corpora and ABI checks.
"""
from pathlib import Path
import json
import subprocess
import sys
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]



from corpus_checks import CorpusGroup
BANDERSNATCH = CorpusGroup()
CRYPTO = CorpusGroup()

# Preserve this native corpus and all original independent reference checks.
@BANDERSNATCH.case
def bandersnatch_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    bs_library = libraries['bandersnatch']
    # Replay the unchanged release-reference proof oracle through the production library, without observer interposition.
    from test_bandersnatch import suite as bs_suite, generated_proofs as bs_generated, bridge_checks as bs_bridge, official_sources as bs_official
    bs_official(False)
    compiled, binary = build(compiler, ROOT/'tests/native/bandersnatch_driver.nim', 'bandersnatch-context',
                             native_libraries=(bs_library,))
    corpus = dict(build=compiled, passed=False, observations=[], reference='spec/bandersnatch-pins.json')
    # Keep each exact fixture request/response and contract diagnostic as reproducible local/CI evidence.
    def bs_query(binary, operation, *values):
        arguments = [(value.hex() or '-') if isinstance(value, bytes) else str(value) for value in values]
        result = command([binary, operation, *arguments], 'bs-context-'+str(len(corpus['observations'])))
        corpus['observations'].append(result)
        assert result['exit_code'] == 0, result
        return result['output'].strip()
    # Failed result access must reject before any default output can be observed.
    def bs_failure(binary):
        result = command([binary, 'F'], 'bs-context-failed-result')
        corpus['failure_probe'] = result
        return result['exit_code'], result['output']
    if compiled['exit_code'] == 0:
        # Preserve original oracle assertions; failures remain visible in the final partial-migration verdict.
        try:
            corpus['vectors'] = bs_suite(binary, query=bs_query, failure_probe=bs_failure)
            corpus['generated'] = bs_generated(binary, query=bs_query)
            corpus['native_boundary'] = bs_bridge()
            corpus['passed'] = True
        except (AssertionError, subprocess.SubprocessError) as error:
            corpus['failure'] = repr(error)
    corpus['requests'] = len(corpus['observations'])
    announce('contextual Bandersnatch vectors/native ABI', corpus['passed'])
    return corpus


# Preserve this native corpus and all original independent reference checks.
@CRYPTO.case
def crypto_corpus(compiler, report, checks, libraries):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    crypto_library = libraries['crypto']
    # Preserve every independent primitive vector, ownership check and joined native-thread workload.
    compiled, binary = build(compiler, ROOT/'tests/native/crypto_driver.nim', 'crypto-driver', crypto_library)
    corpus = dict(build=compiled, passed=False)
    if compiled['exit_code'] == 0:
        # The production-linked corpus has no failure injection or observation wrappers.
        corpus['run'] = command([sys.executable, ROOT/'tests/test_nimony_crypto.py', '--binary', binary], 'crypto-corpus')
        corpus['passed'] = corpus['run']['exit_code'] == 0
        if corpus['passed']:
            # Retain structured independent equation/thread counts alongside the exact reproduction command.
            corpus['counts'] = json.loads(corpus['run']['output'])
    announce('crypto corpus', corpus['passed'])
    return corpus


# Keep existing standalone entry points backed by the same declared task plans.
run_bandersnatch = BANDERSNATCH.run
run_crypto = CRYPTO.run
