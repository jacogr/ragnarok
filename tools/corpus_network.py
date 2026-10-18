"""Feature-owned corpus orchestration; expected results remain in independent test oracles."""
from functools import partial
from pathlib import Path
from corpus_checks import run_corpus
from native_checks import announce

ROOT = Path(__file__).resolve().parents[1]


# Run the network corpora with explicit process, workspace and library inputs.
def run_network(compiler, report, checks, libraries, quic_fixtures, integration_wires):
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
    report['quic_protocol_corpus'] = corpus
    announce('independent SAN/DER/frame boundary corpus', corpus['passed'])
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
    report['integration_corpus'] = corpus
    announce('independent CE digest capture/hash-binding corpus', corpus['passed'])
