#!/usr/bin/env python3
"""Verify Nim nominal-domain safeguards with deliberate compiler rejection fixtures."""
import json
from test_support import ROOT, reject_types


# Each fixture must fail at its intended type boundary, independently of other misuse cases.
def main():
    folder = ROOT/'build/report/types'
    cases = [
        ('root', ROOT/'tests/native/compile_fail/swapped_report_root.nim', ('PackageHash', 'SegmentRoot')),
        ('slot', ROOT/'tests/native/compile_fail/swapped_report_slot.nim', ('AnchorSlot', 'LookupSlot')),
        ('lookup-state', ROOT/'tests/native/compile_fail/swapped_lookup_state.nim', ('LookupStateRoot', 'StateRoot')),
        ('shards', ROOT/'tests/native/compile_fail/raw_erasure_shards.nim', ('ErasureShards', 'uint16')),
    ]
    records = reject_types(cases, folder)
    (folder/'results.json').write_text(json.dumps(records, indent=2)+'\n')
    print(f'PASS {len(records)} report nominal-domain safeguards')


# Imports never launch a compiler or run a negative fixture implicitly.
if __name__ == '__main__':
    main()
