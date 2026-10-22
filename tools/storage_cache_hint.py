# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Request bounded per-file cache hints without asserting eviction, cold storage or physical device reads."""
import errno
import fcntl
import os
import stat


def cache_hint(descriptor, policy):
    """Only a regular read-only descriptor is eligible; no global cache control or namespace mutation occurs."""
    if type(descriptor) is not int or descriptor < 0 or policy not in ('unchanged', 'hint'):
        raise ValueError('Invalid per-file cache hint request')
    if not stat.S_ISREG(os.fstat(descriptor).st_mode) or fcntl.fcntl(descriptor, fcntl.F_GETFL) & os.O_ACCMODE != os.O_RDONLY:
        raise ValueError('Cache hint requires a regular read-only file')
    result = dict(policy=policy, status='not-requested', interface=None, error=None)
    if policy == 'unchanged':
        return result
    try:
        if hasattr(os, 'posix_fadvise') and hasattr(os, 'POSIX_FADV_DONTNEED'):
            # Linux advice is a best-effort request; returned success does not certify eviction.
            result['interface'] = 'POSIX_FADV_DONTNEED'
            os.posix_fadvise(descriptor, 0, 0, os.POSIX_FADV_DONTNEED)
        elif hasattr(fcntl, 'F_NOCACHE'):
            # Darwin bypass advice applies only to this owned descriptor and likewise grants no cold-cache claim.
            result['interface'] = 'F_NOCACHE'
            fcntl.fcntl(descriptor, fcntl.F_NOCACHE, 1)
        else:
            result['status'] = 'unsupported'
            return result
        result['status'] = 'requested'
    except OSError as error:
        # Refusal remains explicit evidence and never silently becomes a warm or cold measurement.
        result.update(status='refused', error=error.errno if error.errno is not None else errno.EIO)
    return result


def validate_hint(value, policy):
    """Admit the exact requested interface/status while keeping unsupported and refused operations distinct."""
    if (type(value) is not dict or set(value) != {'policy', 'status', 'interface', 'error'} or
            value['policy'] != policy or policy not in ('unchanged', 'hint')):
        raise ValueError('Invalid cache hint evidence')
    interface = value['interface']; status = value['status']; error = value['error']
    if policy == 'unchanged':
        valid = status == 'not-requested' and interface is None and error is None
    elif status == 'unsupported':
        valid = interface is None and error is None
    elif status == 'requested':
        valid = interface in ('POSIX_FADV_DONTNEED', 'F_NOCACHE') and error is None
    elif status == 'refused':
        valid = interface in ('POSIX_FADV_DONTNEED', 'F_NOCACHE') and type(error) is int and 0 < error < 1<<31
    else:
        valid = False
    if not valid:
        raise ValueError('Invalid cache hint outcome')
    return value
