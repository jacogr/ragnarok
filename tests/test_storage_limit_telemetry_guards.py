# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from copy import deepcopy
from storage_limit_cgroup import resolve,parse_files,FILES
from storage_limit_status import parse_status
from storage_limit_faults import parse_stat
from storage_limit_psi import parse_psi
from storage_limit_host import validate_snapshot,read
from storage_limit_receipts import validate_limit
import tempfile

class LimitTelemetryGuardTests(unittest.TestCase):
    """Imported pseudo-files cannot normalize malformed or contradictory host evidence."""
    def test_extents_and_duplicate_fields(self):
        """Huge kernel-shaped strings and duplicates fail before resource math."""
        for parser in (parse_status,parse_stat,parse_psi):
            for raw in (None,True,'x'*131073):
                with self.subTest(parser=parser.__name__),self.assertRaises(ValueError):
                    parser(raw)
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'huge';p.write_text('x'*131073)
            with self.assertRaises(ValueError):
                read(p)
    def test_cgroup_mount_escapes_and_ambiguity(self):
        """Neither alternate mounts nor escaped paths select an arbitrary cgroup."""
        mount='10 1 0:1 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n'
        for raw in (mount+mount,mount.replace('/sys/fs/cgroup','/sys/fs/cgroup\\040x'),mount.replace(' / /',' /../host /')):
            with self.assertRaises(ValueError):
                resolve('0::/job\n',raw)
    def test_cgroup_values_are_canonical(self):
        """Every selected interface must exist; max is legal only for limit fields."""
        raw={name:'max\n' if name in ('memory.max','memory.high','memory.swap.max') else '0\n' for name in FILES}
        raw['memory.events']='low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\n'
        self.assertIsNone(parse_files(raw)['memory.max'])
        for field,replacement in (('memory.current','max\n'),('memory.high','01\n'),('memory.swap.current','-1\n')):
            broken=deepcopy(raw);broken[field]=replacement
            with self.assertRaises(ValueError):
                parse_files(broken)
        raw.pop('memory.high')
        with self.assertRaises(ValueError):
            parse_files(raw)
    def test_raw_telemetry_substitution(self):
        """Typed raw-derived values reject plausible booleans and rewritten numeric cells."""
        missing=dict(status='unavailable',reason='os-error',errno=2)
        raw='VmSize: 20 kB\nVmRSS: 10 kB\nVmHWM: 12 kB\nVmSwap: 0 kB\n'
        value=dict(system='Linux',status='observed',process=dict(status='available',raw=raw,value=parse_status(raw)),faults=missing,psi=missing,cgroup=missing)
        validate_snapshot(value)
        for replacement in (True,1,20481):
            bad=deepcopy(value);bad['process']['value']['VmSize']=replacement
            with self.assertRaises(ValueError):
                validate_snapshot(bad)
    def test_limit_does_not_raise_inherited_bound(self):
        """An apparently applied finite cap cannot relax the inherited soft ceiling."""
        cap=128*1024*1024
        value=dict(system='Linux',requested=cap,inherited=[cap//2,None],effective=[cap,None],status='applied')
        with self.assertRaises(ValueError):
            validate_limit(value,cap)
