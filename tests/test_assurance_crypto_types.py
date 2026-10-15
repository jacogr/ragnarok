#!/usr/bin/env python3
"""Verify Nim nominal-domain safeguards with deliberate compiler rejection fixtures."""
import json
from test_support import ROOT, reject_types


# Each fixture must fail at its intended type boundary, independently of other misuse cases.
def main():
    folder = ROOT/'build/assurance-crypto/types'
    cases = [
        ('parent', ROOT/'tests/native/compile_fail/assurance_context_parent.nim', ('AssuranceParent', 'AssuranceAnchor')),
        ('message', ROOT/'tests/native/compile_fail/assurance_context_message.nim', ('EdSignature', 'AssuranceSigningMessage')),
    ]
    records = reject_types(cases, folder)
    (folder/'results.json').write_text(json.dumps(records, indent=2)+'\n')
    print(f'PASS {len(records)} assurance_crypto nominal-domain safeguards')


# Imports never launch a compiler or run a negative fixture implicitly.
if __name__ == '__main__':
    main()
