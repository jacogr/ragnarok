"""Validate per-suite native requirements before any dependency preparation or execution."""
import json
from pathlib import Path
from verification_inventory import UNIT_SUITES, UNIT_LINKS, unique_object


# Require complete, typed records so misspelled fields cannot silently weaken a native profile.
def validate_requirements(records):
    if not isinstance(records, dict) or set(records) != set(UNIT_SUITES):
        # Coverage remains checked against the independently maintained execution inventory.
        raise ValueError('Native requirements must cover exactly the registered suites')
    fields = {'directory', 'libraries', 'includes', 'observers', 'defines', 'prepared'}
    allowed = {
        'libraries': {'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic'},
        'includes': {'crypto', 'bandersnatch', 'quic'},
        'observers': {'setup_new', 'setup_free', 'key_new', 'key_free', 'verify', 'commit', 'ring_verify'},
        'defines': {'integration'},
    }
    for name, record in records.items():
        # Every suite explicitly declares its source family, linking and fresh-fixture requirements.
        if not isinstance(record, dict) or set(record) != fields:
            raise ValueError('Invalid native requirement fields: '+name)
        if record['directory'] not in ('codec', 'state', 'crypto', 'quic') or type(record['prepared']) is not bool:
            raise ValueError('Invalid native source or fixture requirement: '+name)
        for field, choices in allowed.items():
            # Reject arbitrary compiler arguments and duplicate settings, retaining declared order.
            values = record[field]
            if not isinstance(values, list) or any(not isinstance(value, str) or value not in choices for value in values) or len(values) != len(set(values)):
                raise ValueError('Invalid native '+field+': '+name)
        primary = UNIT_LINKS.get(name)
        if (record['libraries'][-1] if record['libraries'] else None) != primary:
            # The last library is the established primary profile; supplementary libraries precede it.
            raise ValueError('Native primary library mismatch: '+name)
        if (record['directory'] == 'codec') != (name not in UNIT_LINKS):
            # Only the existing dependency-free codec group may use directory discovery.
            raise ValueError('Native batch directory mismatch: '+name)
        if bool(record['includes']) != bool(primary) or (record['observers'] and 'bandersnatch_observer' not in record['libraries']):
            # Header and observer configuration must have corresponding prepared native libraries.
            raise ValueError('Native header or observer mismatch: '+name)
    return records


# Duplicate JSON keys are fatal at every level, just as in the main verification inventory.
NATIVE_REQUIREMENTS = validate_requirements(json.loads(
    Path(__file__).with_suffix('.json').read_text(), object_pairs_hook=unique_object))
