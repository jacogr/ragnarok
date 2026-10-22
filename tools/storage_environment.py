# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Record filesystem geometry and inherited memory limits without guessing cache or device behavior."""
import os
from pathlib import Path
import platform
import resource
import subprocess

POLICY = 'unchanged OS cache; no eviction or memory-pressure control'


def physical_memory_bytes():
    """Use documented host counters where available; unavailable capacity remains explicit None."""
    if 'SC_PHYS_PAGES' in os.sysconf_names:
        pages = os.sysconf('SC_PHYS_PAGES')
        if pages > 0:
            return pages*os.sysconf('SC_PAGE_SIZE')
    if platform.system() == 'Darwin':
        return int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True).strip())
    return None


def environment(folder):
    """Observe the owned output filesystem and actual inherited limits, excluding paths and unrelated environment."""
    folder = Path(folder); stat = os.statvfs(folder)
    limits = {}
    for name, selector in (('address_space', resource.RLIMIT_AS), ('data', resource.RLIMIT_DATA)):
        # Limits are recorded observations; this runner neither changes them nor claims host enforcement.
        limits[name] = [None if value == resource.RLIM_INFINITY else value for value in resource.getrlimit(selector)]
    result = dict(cache_policy=POLICY, block_bytes=stat.f_bsize, fragment_bytes=stat.f_frsize,
                  capacity_bytes=stat.f_blocks*stat.f_frsize, available_bytes=stat.f_bavail*stat.f_frsize,
                  device_id=folder.stat().st_dev, read_only=bool(stat.f_flag & os.ST_RDONLY),
                  physical_memory_bytes=physical_memory_bytes(), inherited_limits=limits)
    validate_environment(result)
    return result


def validate_environment(value):
    """Unsupported capacity stays unavailable; malformed geometry or substituted cache policy refuses."""
    fields = {'cache_policy', 'block_bytes', 'fragment_bytes', 'capacity_bytes', 'available_bytes',
              'device_id', 'read_only', 'physical_memory_bytes', 'inherited_limits'}
    if type(value) is not dict or set(value) != fields or value['cache_policy'] != POLICY:
        raise ValueError('Invalid storage environment policy/fields')
    for key in ('block_bytes', 'fragment_bytes', 'capacity_bytes', 'available_bytes', 'device_id'):
        # Python arithmetic cannot wrap; stored evidence still requires bounded nonboolean integer extents.
        if type(value[key]) is not int or not 0 <= value[key] < 1<<63:
            raise ValueError('Invalid storage environment extent')
    if (value['block_bytes'] == 0 or value['fragment_bytes'] == 0 or value['available_bytes'] > value['capacity_bytes'] or
            type(value['read_only']) is not bool):
        raise ValueError('Invalid storage filesystem geometry')
    memory = value['physical_memory_bytes']
    if memory is not None and (type(memory) is not int or not 0 < memory < 1<<63):
        raise ValueError('Invalid storage physical memory observation')
    limits = value['inherited_limits']
    if type(limits) is not dict or set(limits) != {'address_space', 'data'}:
        raise ValueError('Invalid inherited storage limit plan')
    for pair in limits.values():
        if (type(pair) is not list or len(pair) != 2 or
                any(v is not None and (type(v) is not int or not 0 <= v < 1<<63) for v in pair) or
                (pair[1] is not None and (pair[0] is None or pair[0] > pair[1]))):
            raise ValueError('Invalid inherited storage limit')
    return value
