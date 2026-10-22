# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from storage_limit_cgroup import resolve,scalar,events

class LimitCgroupTests(unittest.TestCase):
    """Read-only namespace resolution never walks a guessed cgroup path."""
    def test_mount_root(self):
        """Bind current membership relative to the actual visible mount root."""
        mount='10 1 0:1 /tenant /sys/fs/cgroup rw - cgroup2 cgroup rw\n'
        self.assertEqual(resolve('0::/tenant/job\n',mount),'/sys/fs/cgroup/job')
        for member in ('0::/tenant/../host\n','0::/other\n','0::/tenant\n0::/tenant/job\n'):
            with self.assertRaises(ValueError):
                resolve(member,mount)
    def test_limits_and_events(self):
        """Unlimited differs from zero; event aliases and omissions fail."""
        self.assertIsNone(scalar('max\n',True)); self.assertEqual(scalar('0\n'),0)
        raw='low 0\nhigh 1\nmax 2\noom 3\noom_kill 4\n'
        self.assertEqual(events(raw)['oom_kill'],4)
        for broken in (raw+'oom 0\n',raw.replace('oom_kill 4\n','')):
            with self.assertRaises(ValueError):
                events(broken)
