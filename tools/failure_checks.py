"""Run strict assertion probes and fixed state-result suites without changing native diagnostics."""
import json
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


# Reject lost, duplicated or vacuous fixed cases before compiling any probe binaries.
def load_suites(path):
    suites = json.loads(path.read_text(), object_pairs_hook=unique_object)
    for group, suite in suites.items():
        # Counts remain independently declared in the authoritative coverage inventory.
        cases = [case_details(suite, case) for case in suite['cases']]
        names = [case['name'] for case in cases]
        identities = [json.dumps(case['identity'], sort_keys=True) for case in cases]
        if (len(cases) != FAILURE_COUNTS[group] or len(set(names)) != len(cases)
                or len(set(identities)) != len(cases)
                or not all(case['diagnostic'] for case in cases)):
            # Empty diagnostics could allow an unrelated assertion to masquerade as the intended guard.
            raise ValueError('Invalid runtime failure cases: '+group)
    return suites


FAILURE_SUITES = load_suites(Path(__file__).with_name('failure_suites.json'))


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
