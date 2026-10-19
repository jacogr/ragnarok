# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Feature-owned corpus orchestration; expected results remain in independent test oracles.

Exposes run_network to execute protocol/telemetry corpora and record their verdicts.
"""
from functools import partial
from pathlib import Path
from corpus_checks import run_corpus, CorpusGroup
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]



CORPORA = CorpusGroup()

# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def quic_protocol_corpus(compiler, report, checks, libraries, quic_fixtures, integration_wires):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    quic_library = libraries['quic']
    # Compare identity/framing outcomes with an independent arbitrary-precision oracle and public DER fixtures.
    from quic_protocol_oracle import requests as protocol_requests
    lines, expected, groups = protocol_requests(quic_fixtures)
    source = BUILD/'quic-protocol-requests.txt'
    # Keep exact status/identity/length/extent observations; incomplete results expose no payload metadata.
    corpus = execute_corpus(ROOT / 'tests/native/quic_protocol_driver.nim', 'quic-protocol-driver',
                        source, lines, expected, 'quic-protocol-corpus',
                        metadata=dict(groups=groups,
                                      scope='pinned SAN/DER identity and structural CE framing; no TLS handshake or fixture eligibility claim'), expected_hash=True,
                        quic_library=quic_library)
    announce('independent SAN/DER/frame boundary corpus', corpus['passed'])
    return corpus


# Run this independently declared corpus with its original checks and dependencies.
@CORPORA.case
def integration_corpus(compiler, report, checks, libraries, quic_fixtures, integration_wires):
    BUILD = checks.folder
    build, command = checks.build, checks.command
    execute_corpus = partial(run_corpus, build, command, compiler)
    crypto_library = libraries['crypto']
    quic_library = libraries['quic']
    # Compose independently parsed full C.2 wires and hashlib keys through the enabled production ABI.
    from integration_oracle import requests as integration_requests
    lines, expected = integration_requests(integration_wires)
    source = BUILD/'integration-requests.txt'
    # Compare complete serialized bytes and failure ordering, not only a self-generated round trip.
    corpus = execute_corpus(ROOT / 'tests/native/integration_driver.nim', 'integration-driver',
                        source, lines, expected, 'integration-corpus',
                        metadata=dict(scope='CE fixture codec/crypto composition; no authenticated transport or normative digest/preimage relationship'), expected_hash=True,
                        crypto_library=crypto_library,
                        defines=('integration',))
    announce('independent CE digest capture/hash-binding corpus', corpus['passed'])
    return corpus


# Existing callers use the same entry point; the declared tasks own its complete plan.
run_network = CORPORA.run
