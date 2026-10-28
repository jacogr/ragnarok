# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Strict versioned policy receipts for current public comparison owners; historical logs stay explicit."""


def policy_receipt(output, requested):
    """Remove one terminal receipt only after checking requested policy, availability and actual native work."""
    lines = output.splitlines()
    fields = lines.pop().split(',') if lines else []
    if len(fields) != 10 or fields[:3] != ['PVM_POLICY', '1', requested]:
        raise ValueError('Missing or foreign PVM policy receipt')
    if requested not in ('interpreted', 'jit') or any(x not in ('0', '1') for x in fields[3:6]):
        raise ValueError('Invalid PVM policy availability')
    if any(not x.isascii() or not x.isdecimal() or len(x) > 20 or
           (len(x) > 1 and x.startswith('0')) or int(x) >= 2**64 for x in fields[7:]):
        raise ValueError('Invalid PVM policy counters')
    built, supported, fallback = map(int, fields[3:6])
    fragments, calls, operations = map(int, fields[7:])
    actual = 'jit' if operations else 'interpreted'
    if fields[6] != actual or fallback != int(requested == 'jit'):
        raise ValueError('PVM policy actual/fallback disagreement')
    if (requested == 'interpreted' or not built or not supported) and any((fragments, calls, operations)):
        raise ValueError('Native activity under interpreted or unavailable policy')
    if supported and not built or bool(calls) != bool(operations) or calls and not fragments:
        raise ValueError('Impossible PVM policy native counters')
    return '\n'.join(lines)+'\n', dict(version=1, requested=requested, actual=actual,
        jit_built=bool(built), platform_supported=bool(supported), fallback_enabled=bool(fallback),
        fragments=fragments, calls=calls, operations=operations)
