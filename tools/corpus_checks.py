"""Compare native corpus observations without sharing protocol logic with independent references."""
import hashlib


# Mutate one corpus report after a successful build; command owns timeouts and complete retained logs.
# Expected rows are independently generated before execution. Extra coverage predicates remain explicit
# at the call site. Failed builds never execute stale binaries or replace their existing evidence.
def compare_corpus(corpus, command, arguments, name, expected, *, complete=True):
    if corpus['build']['exit_code'] != 0:
        # The caller's failed build report remains authoritative, including its original hash fields.
        return
    result = command(arguments, name)
    output = result.pop('output')
    actual = output.splitlines()
    corpus.update(run=result, passed=result['exit_code'] == 0 and actual == expected and complete,
                  actual_sha256=hashlib.sha256(output.encode()).hexdigest(),
                  expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
    if not corpus['passed']:
        # Missing/extra rows, process failures and coverage failures all retain the original mismatch index.
        corpus['first_mismatch'] = next((i for i, (a, e) in enumerate(zip(actual, expected)) if a != e),
                                        min(len(actual), len(expected)))
