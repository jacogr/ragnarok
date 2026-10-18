# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run strict assertion probes and fixed state-result suites without changing native diagnostics.

Exposes validated FAILURE_SUITES, strict probe_failure and run_failure_suite orchestration with
retained diagnostics.
"""
import json
import re
from pathlib import Path
from native_checks import ROOT, announce
from verification_inventory import FAILURE_COUNTS, unique_object


# Expand shared labels and argument fields without evaluating code from inventory data.
# Explicit case values override defaults for unusual factories, variants and argument layouts.
def case_details(suite, case):
    identity = case['identity']
    arguments = case['arguments'] if 'arguments' in case else [identity[key] for key in suite['argument_fields']]
    return dict(identity=identity, arguments=arguments,
                name=case['name'] if 'name' in case else suite['name_template'].format(**identity),
                description=case['description'] if 'description' in case else suite['description_template'].format(**identity),
                diagnostic=case['diagnostic'] if 'diagnostic' in case else suite['diagnostic'])


# Reject unknown keys instead of silently ignoring misspelled fields that could weaken a probe.
def check_fields(value, allowed, required, context):
    if not isinstance(value, dict):
        # A family/case is an object, never a list or scalar with coincidentally matching contents.
        raise ValueError('Expected an object in '+context)
    unknown, missing = set(value) - allowed, required - set(value)
    if unknown or missing:
        # Include exact fields so inventory edits can be repaired without native builds.
        raise ValueError('Invalid fields in '+context+': unknown='+str(sorted(unknown))
                         +', missing='+str(sorted(missing)))


# Validate one family's source, build profile and expanded cases before any process can execute.
def validate_suite(group, suite, root=ROOT):
    check_fields(suite, {'source', 'build_name', 'crypto_library', 'native_libraries', 'quic_library',
                        'defines', 'name_template', 'description_template', 'diagnostic',
                        'argument_fields', 'cases'}, {'source', 'build_name', 'cases'}, group)
    if group not in FAILURE_COUNTS:
        # Coverage counts remain independently declared, including the explicit specialized families.
        raise ValueError('Unknown failure family: '+group)
    for field in ('name_template', 'description_template', 'diagnostic'):
        # Optional defaults must be meaningful strings even when current cases override them.
        if field in suite and (not isinstance(suite[field], str) or not suite[field].strip()):
            raise ValueError('Invalid '+field+' in '+group)
    source = suite['source']
    if (not isinstance(source, str) or Path(source).is_absolute() or '..' in Path(source).parts
            or not source.endswith('.nim') or not (root/source).is_file()):
        # A missing or escaping source cannot be satisfied by a stale compiled driver.
        raise ValueError('Invalid source in '+group)
    for field, allowed in (('crypto_library', {None, 'crypto', 'observer'}),
                           ('quic_library', {None, 'quic'})):
        # The two header/linking paths accept only their prepared library profiles.
        if not isinstance(suite.get(field), (str, type(None))) or suite.get(field) not in allowed:
            raise ValueError('Invalid '+field+' in '+group)
    for field in ('native_libraries', 'defines', 'argument_fields'):
        # Lists are ordered; duplicate flags or fields usually indicate an accidental copied entry.
        values = suite.get(field, [])
        if (not isinstance(values, list) or not all(isinstance(v, str) and v for v in values)
                or len(values) != len(set(values))):
            raise ValueError('Invalid '+field+' in '+group)
    if not set(suite.get('native_libraries', [])) <= {'bandersnatch', 'bandersnatch_observer'}:
        # Native owner libraries use the maintained Bandersnatch header and ABI path.
        raise ValueError('Invalid native_libraries in '+group)
    if not all(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', flag) for flag in suite.get('defines', [])):
        # Defines are compiler symbols, not arbitrary command-line options.
        raise ValueError('Invalid defines in '+group)
    raw = suite['cases']
    if not isinstance(raw, list) or len(raw) != FAILURE_COUNTS[group]:
        # A missing or vacuous family must fail before a successful sibling can mask lost coverage.
        raise ValueError('Invalid case count in '+group)
    expanded = []
    for index, case in enumerate(raw):
        # Validate raw fields before formatting suite defaults with the individual identity.
        context = group+' case '+str(index)
        check_fields(case, {'identity', 'arguments', 'name', 'description', 'diagnostic'}, {'identity'}, context)
        identity = case['identity']
        if (not isinstance(identity, dict) or not identity or {'passed', 'run'}.intersection(identity)
                or not all(isinstance(k, str) and type(v) in (str, int, bool) for k, v in identity.items())):
            raise ValueError('Invalid identity in '+context)
        try:
            details = case_details(suite, case)
        except (KeyError, IndexError, AttributeError, TypeError, ValueError) as error:
            # Malformed defaults must identify their family instead of surfacing as an opaque lookup failure.
            raise ValueError('Invalid defaults in '+context+': '+str(error)) from error
        if (not isinstance(details['arguments'], list)
                or not all(type(v) in (str, int) for v in details['arguments'])
                or not all(isinstance(details[key], str) and details[key].strip()
                           for key in ('name', 'description', 'diagnostic'))):
            raise ValueError('Invalid arguments or diagnostics in '+context)
        expanded.append(details)
    names = [suite['build_name'], *(case['name'] for case in expanded)]
    if not all(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9_-]+', name) for name in names):
        # Names become log/cache filenames and must remain unambiguous single path components.
        raise ValueError('Invalid build or log name in '+group)
    identities = [json.dumps(case['identity'], sort_keys=True) for case in expanded]
    if len(set(identities)) != len(identities):
        # Counting duplicate identities would conceal an omitted accessor or origin.
        raise ValueError('Duplicate failure identity in '+group)
    return [suite['build_name']+'-build', *(case['name'] for case in expanded)]


# Discover one file per family; explicit calls in run_failures retain the historical execution order.
def load_suites(path, root=ROOT):
    suites, logs = {}, set()
    files = sorted(path.glob('*.json'))
    if not files:
        # A missing directory must not silently turn the runtime workload into zero suites.
        raise ValueError('No failure suites in '+str(path))
    for source in files:
        # A filename supplies the family identity, avoiding a second registry that every feature must edit.
        group = source.stem
        suite = json.loads(source.read_text(), object_pairs_hook=unique_object)
        names = validate_suite(group, suite, root)
        if len(names) != len(set(names)) or logs.intersection(names):
            # Build and probe logs share a directory, including across different families.
            raise ValueError('Duplicate failure log name in '+group)
        logs.update(names)
        suites[group] = suite
    return suites


FAILURE_SUITES = load_suites(Path(__file__).with_name('failure_suites'))


# Execute one child, retain its full evidence and append the original identity and strict verdict.
# The caller owns build success; command owns timeout handling and log capture. Exceptions propagate.
def probe_failure(command, rows, arguments, name, diagnostic, description, *, environment=None, **identity):
    if environment is None:
        # Ordinary probes inherit exactly the command runner's original environment behavior.
        result = command(arguments, name)
    else:
        # Fixture-dependent probes keep their explicit, isolated environment unchanged.
        result = command(arguments, name, environment)
    passed = (result['exit_code'] == 1 and diagnostic in result['output']
              and '[AssertionDefect]' in result['output'])
    rows.append(dict(**identity, passed=passed, run=result))
    announce(description, passed)


# Compile one fixed suite using its existing library profile, then run each case in data-file order.
def run_failure_suite(compiler, report, libraries, build, command, group):
    suite = FAILURE_SUITES[group]
    options = {}
    if suite.get('quic_library') is not None:
        # Library names select an already prepared transport profile.
        options['quic_library'] = libraries[suite['quic_library']]
    if suite.get('native_libraries'):
        # Preserve the original ordered native link set for cryptographic owner tests.
        options['native_libraries'] = tuple(libraries[name] for name in suite['native_libraries'])
    if 'defines' in suite:
        # Integration probes retain their explicitly enabled compilation profile.
        options['defines'] = tuple(suite['defines'])
    crypto = libraries[suite['crypto_library']] if suite.get('crypto_library') is not None else None
    compiled, binary = build(compiler, ROOT/suite['source'], suite['build_name'], crypto, **options)
    report[group+'_build'] = compiled
    if compiled['exit_code'] != 0:
        # Failed builds must never execute a stale binary or manufacture passing probe rows.
        return
    for case in suite['cases']:
        # Every attempted access remains a separate process with its exact command, diagnostic and log name.
        case = case_details(suite, case)
        probe_failure(command, report[group], [binary, *case['arguments']], case['name'],
                      case['diagnostic'], case['description'], **case['identity'])
