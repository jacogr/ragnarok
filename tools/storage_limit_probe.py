# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prove bounded positive mapping and over-ceiling allocation refusal in one disposable process."""
import errno
import json
import mmap
import os
import sys
from storage_limit_apply import apply_cap
from storage_limit_budget import budget,MIB,natural


def probe(cap):
    """Touch at most one MiB; the negative mapping requests only virtual address space and is never touched."""
    budget(cap); receipt=apply_cap(cap)
    result=dict(limit=receipt,positive_bytes=MIB,page_bytes=os.sysconf('SC_PAGE_SIZE'))
    if receipt['status']!='applied':
        return dict(result,status='unavailable')
    try:
        with mmap.mmap(-1,MIB) as positive:
            # Every page in the fixed small positive control must accept and preserve its byte.
            for offset in range(0,MIB,result['page_bytes']):
                positive[offset]=93
                if positive[offset]!=93:
                    raise RuntimeError('Positive memory probe mismatch')
            try:
                negative=mmap.mmap(-1,cap)
            except OSError as error:
                if error.errno!=errno.ENOMEM:
                    raise
                return dict(result,status='enforced',refusal='ENOMEM',negative_bytes=cap)
            except MemoryError:
                return dict(result,status='enforced',refusal='MemoryError',negative_bytes=cap)
            else:
                # Unexpected success is closed without touching a potentially large virtual mapping.
                negative.close()
                return dict(result,status='not-enforced',negative_bytes=cap)
    except (OSError,MemoryError):
        return dict(result,status='unavailable',reason='positive-allocation')


# Only a separately started process invokes the mutating probe; importing tooling is read-only.
if __name__=='__main__':
    if len(sys.argv)!=2:
        raise SystemExit('Expected one bounded cap')
    print(json.dumps(probe(natural(sys.argv[1])),sort_keys=True))
