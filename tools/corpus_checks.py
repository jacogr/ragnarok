# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare native corpus observations without sharing protocol logic with independent references.

Exposes compare_corpus and run_corpus for strict expected/observed comparison, process handling
and report updates.
"""
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


# Execute the standard request-file corpus path; callers retain independent generation and coverage rules.
# Metadata describes corpus-specific evidence. expected_hash preserves hashes historically emitted even
# for a failed build; successful execution always records both expected and actual output hashes.
def run_corpus(build, command, compiler, driver, build_name, source, lines, expected, run_name,
               *, metadata=None, expected_hash=False, complete=True, **build_options):
    source.write_text('\n'.join(lines)+'\n')
    compiled, binary = build(compiler, driver, build_name, **build_options)
    corpus = dict(build=compiled, requests=len(lines), passed=False,
                  requests_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), **(metadata or {}))
    if expected_hash:
        # Some historical reports retain independent expected evidence when compilation fails.
        corpus['expected_sha256'] = hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest()
    compare_corpus(corpus, command, [binary, source], run_name, expected, complete=complete)
    return corpus


class CorpusGroup:
    """Own ordered named callables; one function declaration supplies scheduling and expected report identity."""

    def __init__(self, *, order=None, resources=()):
        """Own a dependency rank and ordered resource names without preparing or executing any corpus."""
        self.order = order
        self.resources = tuple(resources)
        self.tasks = {}

    def case(self, function):
        """Register one corpus by its function name, refusing repeated or malformed identities."""
        name = function.__name__
        if not name.endswith('_corpus') or name in self.tasks:
            # Duplicate registration could overwrite required coverage before scheduling.
            raise ValueError('Invalid or duplicate corpus task: '+name)
        self.tasks[name] = function
        return function

    def run(self, compiler, report, checks, libraries, *fixtures):
        """Execute the declared order and publish each returned verdict under its single registered key."""
        for name, function in self.tasks.items():
            # A report key is owned by exactly one task, including across feature groups.
            if name in report:
                raise ValueError('Duplicate corpus report: '+name)
            observed = function(compiler, report, checks, libraries, *fixtures)
            if not isinstance(observed, dict) or type(observed.get('passed')) is not bool:
                # A missing verdict must never be interpreted as an empty successful corpus.
                raise ValueError('Missing corpus verdict: '+name)
            report[name] = observed
