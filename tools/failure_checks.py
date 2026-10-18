"""Run strict assertion probes and fixed state-result suites without changing native diagnostics."""
import json
from pathlib import Path
from native_checks import ROOT, announce
from verification_inventory import FAILURE_COUNTS, unique_object


# Reject lost, duplicated or vacuous fixed cases before compiling any probe binaries.
def load_suites(path):
    suites = json.loads(path.read_text(), object_pairs_hook=unique_object)
    for group, suite in suites.items():
        # Counts remain independently declared in the authoritative coverage inventory.
        cases = suite['cases']
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
    compiled, binary = build(compiler, ROOT/suite['source'], suite['build_name'],
                             libraries[suite['crypto_library']],
                             native_libraries=tuple(libraries[name] for name in suite['native_libraries']))
    report[group+'_build'] = compiled
    if compiled['exit_code'] != 0:
        # Failed builds must never execute a stale binary or manufacture passing probe rows.
        return
    for case in suite['cases']:
        # Every attempted access remains a separate process with its exact command, diagnostic and log name.
        probe_failure(command, report[group], [binary, *case['arguments']], case['name'],
                      case['diagnostic'], case['description'], **case['identity'])
