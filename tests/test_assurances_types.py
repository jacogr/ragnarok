#!/usr/bin/env python3
"""Verify Nim nominal-domain safeguards with deliberate compiler rejection fixtures."""
import json
from test_support import ROOT, reject_types


# Each fixture must fail at its intended type boundary, independently of other misuse cases.
def main():
    folder = ROOT/'build/assurances/types'
    cases = [
        ('anchor', ROOT/'tests/native/compile_fail/assurances_anchor.nim', ('AssuranceAnchor', 'AssuranceSignature')),
        ('index', ROOT/'tests/native/compile_fail/assurances_index.nim', ('ValidatorIndex', 'CoreCount')),
        ('config', ROOT/'tests/native/compile_fail/assurances_config.nim', ('CoreCount', 'ValidatorCount')),
    ]
    records = reject_types(cases, folder)
    (folder/'results.json').write_text(json.dumps(records, indent=2)+'\n')
    print(f'PASS {len(records)} assurances nominal-domain safeguards')


# Imports never launch a compiler or run a negative fixture implicitly.
if __name__ == '__main__':
    main()
