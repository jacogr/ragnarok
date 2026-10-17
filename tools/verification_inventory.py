"""Load merge-friendly verification data while retaining the harness's public value types."""
import json
from pathlib import Path


# JSON normally overwrites repeated keys; a lost guard or suite must fail before verification runs.
def unique_object(pairs):
    result = {}
    for key, value in pairs:
        # Reject duplicates at every object level, including inventory section names.
        if key in result:
            raise ValueError('Duplicate verification inventory key: '+key)
        result[key] = value
    return result


# Keep each case unique while restoring tuple records used by runtime probe generation.
def cases(values):
    result = tuple(tuple(value) if isinstance(value, list) else value for value in values)
    if len(result) != len(set(result)):
        # Duplicate cases can otherwise inflate totals while masking missing coverage.
        raise ValueError('Duplicate verification inventory case')
    return result


_DATA = json.loads(Path(__file__).with_suffix('.json').read_text(), object_pairs_hook=unique_object)

# Explicit exports keep missing sections fatal and preserve existing consumer interfaces.
UNIT_SUITES = cases(_DATA['UNIT_SUITES'])
PRIVATE = _DATA['PRIVATE']
NOMINAL = _DATA['NOMINAL']
REPORT_MEMBERS = cases(_DATA['REPORT_MEMBERS'])
ASSURANCE_MEMBERS = cases(_DATA['ASSURANCE_MEMBERS'])
GUARANTEE_MEMBERS = cases(_DATA['GUARANTEE_MEMBERS'])
TICKET_MEMBERS = cases(_DATA['TICKET_MEMBERS'])
DISPUTE_MEMBERS = cases(_DATA['DISPUTE_MEMBERS'])
PACKAGE_MEMBERS = cases(_DATA['PACKAGE_MEMBERS'])
HEADER_MEMBERS = cases(_DATA['HEADER_MEMBERS'])
HEADER_OPTIONAL = cases(_DATA['HEADER_OPTIONAL'])
BLOCK_MEMBERS = cases(_DATA['BLOCK_MEMBERS'])
BLOCK_WRONG = cases(_DATA['BLOCK_WRONG'])
BITS_MEMBERS = cases(_DATA['BITS_MEMBERS'])
COLLECTION_MEMBERS = cases(_DATA['COLLECTION_MEMBERS'])
C2_MEMBERS = cases(_DATA['C2_MEMBERS'])
C2_VARIANTS = cases(_DATA['C2_VARIANTS'])
CRYPTO_MEMBERS = cases(_DATA['CRYPTO_MEMBERS'])
LAYOUT_MEMBERS = cases(_DATA['LAYOUT_MEMBERS'])
LAYOUT_VARIANTS = list(cases(_DATA['LAYOUT_VARIANTS']))
TRIE_ORIGINS = cases(_DATA['TRIE_ORIGINS'])
SAFROLE_MEMBERS = cases(_DATA['SAFROLE_MEMBERS'])
AUTHORIZATION_MEMBERS = cases(_DATA['AUTHORIZATION_MEMBERS'])
CONSENSUS_MEMBERS = cases(_DATA['CONSENSUS_MEMBERS'])
STATE_DISPUTES_MEMBERS = cases(_DATA['STATE_DISPUTES_MEMBERS'])
CONTRACTS = _DATA['CONTRACTS']
HISTORY_MEMBERS = cases(_DATA['HISTORY_MEMBERS'])
AVAILABILITY_MEMBERS = cases(_DATA['AVAILABILITY_MEMBERS'])
PRIVILEGES_MEMBERS = cases(_DATA['PRIVILEGES_MEMBERS'])
STATISTICS_MEMBERS = cases(_DATA['STATISTICS_MEMBERS'])
WORKQUEUES_MEMBERS = cases(_DATA['WORKQUEUES_MEMBERS'])
OUTPUTS_MEMBERS = cases(_DATA['OUTPUTS_MEMBERS'])
ACCOUNTS_MEMBERS = cases(_DATA['ACCOUNTS_MEMBERS'])
SERVICE_VALUES_MEMBERS = cases(_DATA['SERVICE_VALUES_MEMBERS'])
REQUESTS_MEMBERS = cases(_DATA['REQUESTS_MEMBERS'])
REQUESTS_FIELDS = cases(_DATA['REQUESTS_FIELDS'])
COMPOSITION_MEMBERS = cases(_DATA['COMPOSITION_MEMBERS'])
EARLY_NOMINAL = {key: tuple(value) for key, value in _DATA['EARLY_NOMINAL'].items()}
ASSURANCE_CONTEXT_MEMBERS = cases(_DATA['ASSURANCE_CONTEXT_MEMBERS'])
GUARANTEE_MESSAGE_MEMBERS = cases(_DATA['GUARANTEE_MESSAGE_MEMBERS'])
INTEGRATION_MEMBERS = cases(_DATA['INTEGRATION_MEMBERS'])
BS_MEMBERS = cases(_DATA['BS_MEMBERS'])
PRIMITIVE_MEMBERS = cases(_DATA['PRIMITIVE_MEMBERS'])
PRIMITIVE_ERRORS = cases(_DATA['PRIMITIVE_ERRORS'])
OWNED_MEMBERS = cases(_DATA['OWNED_MEMBERS'])
COMPOSITE_MEMBERS = cases(_DATA['COMPOSITE_MEMBERS'])
MEMBERS = cases(_DATA['MEMBERS'])
FAILURE_COUNTS = _DATA['FAILURE_COUNTS']
CORPUS_NAMES = cases(_DATA['CORPUS_NAMES'])
ARC_SUITES = _DATA['ARC_SUITES']
UNIT_LINKS = _DATA['UNIT_LINKS']

# Link and allocation profiles must refer to suites that discovery actually executes.
if not (ARC_SUITES.keys() | UNIT_LINKS.keys()) <= set(UNIT_SUITES):
    raise ValueError('Verification profile references an unknown native suite')
