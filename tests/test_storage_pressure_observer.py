# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject false resident-pressure evidence, unsafe service targets and uncapped/uncleaned launches."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import storage_pressure_metrics as metrics
import storage_pressure_scope as scope
import storage_pressure_child as child
from types import SimpleNamespace

UNIT = 'ragnarok-storage-pressure-'+'a'*32+'.service'


def snapshot():
    """A minimal complete kernel receipt keeps byte gauges distinct from event counters."""
    raw = {key: '0\n' for key in metrics.FILES}
    raw.update({'memory.high': '67108864\n', 'memory.max': '67108864\n',
                'memory.events.local': 'low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\n',
                'memory.stat': 'anon 0\nfile 0\npgfault 0\npgmajfault 0\npgscan 0\npgsteal 0\n',
                'memory.pressure': 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n',
                'io.stat': ''})
    return raw


class PressureObserverTests(unittest.TestCase):
    """Signal/resource interpretation must come from private kernel receipts rather than assumptions."""

    def test_wait4_and_kernel_peaks_need_no_live_proc_sampling(self):
        """Reads occur only outside child execution, avoiding the observed procfs ENOMEM under caps."""
        self.run_observer_case(False)

    def test_deadline_kills_child_and_restores_alarm(self):
        """A stalled child remains a distinct observation and cannot leave the caller's timer armed."""
        self.run_observer_case(True)

    def run_observer_case(self, timeout):
        """Drive real receipt parsing around a fake wait4 child, with timer ownership checked explicitly."""
        member = '0::/system.slice/'+UNIT+'\n'
        mounts = '29 23 0:26 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n'
        events = []
        process = SimpleNamespace(pid=17, returncode=None)
        usage = SimpleNamespace(ru_maxrss=4, ru_minflt=2, ru_majflt=0, ru_inblock=1, ru_oublock=0)
        handlers = []
        def register(sig, callback):
            handlers.append(callback)
            return 0
        def waiting(pid, options):
            events.append('wait')
            if timeout:
                handlers[0](14, None)
            return (17, 9 if timeout else 0, usage)
        def reading(group):
            events.append('read')
            return snapshot()
        with tempfile.TemporaryDirectory() as owned:
            log = Path(owned)/'native.log'
            def spawning(*args, **kwargs):
                log.with_suffix('.membership.log').write_text(json.dumps(dict(
                    pid=17, membership_raw=member, oom_score_adj_raw='1000\n')))
                return process
            with patch.object(child, 'read_raw', side_effect=reading), \
                    patch.object(child.subprocess, 'Popen', side_effect=spawning), \
                    patch.object(child.os, 'wait4', side_effect=waiting), \
                    patch.object(child.os, 'kill') as kill, \
                    patch.object(child.signal, 'signal', side_effect=register), \
                    patch.object(child.signal, 'alarm') as alarm:
                row = child.observe(Path('/sys/fs/cgroup/system.slice')/UNIT, ['/tmp/native'], log, mounts)
            self.assertEqual(events, ['read', 'wait', 'read'])
            self.assertEqual(row['resources']['peak_rss_bytes'], 4096)
            self.assertEqual(row['outcome'], 'observer-timeout' if timeout else 'completed')
            self.assertEqual([call.args[0] for call in alarm.call_args_list], [35, 0])
            self.assertEqual(handlers[-1], 0)
            self.assertEqual(kill.call_count, int(timeout))

    def test_kernel_zero_elision_and_optional_latency_gauges(self):
        """Device-only lines mean zero read/write counters; optional gauges must never be subtracted."""
        zero = dict(rbytes=0, wbytes=0, rios=0, wios=0)
        self.assertEqual(metrics.io_counters('8:0 \n'), {'8:0': zero})
        self.assertEqual(metrics.io_counters('8:0 depth=2 cost.vrate=100.00\n'), {'8:0': zero})
        self.assertEqual(metrics.io_counters('8:0 rbytes=1 wbytes=0 rios=1 wios=0 depth=1\n'),
                         {'8:0': dict(rbytes=1, wbytes=0, rios=1, wios=0)})
        with self.assertRaises(ValueError):
            metrics.io_counters('8:0 rbytes=1\n')

    def test_gauges_may_fall_while_counters_increase(self):
        """Resident bytes are not cumulative; reclaim counters and PSI totals are."""
        before = snapshot()
        before['memory.current'] = '1000\n'
        after = snapshot()
        after['memory.events.local'] = 'low 0\nhigh 2\nmax 1\noom 0\noom_kill 0\n'
        evidence = metrics.derive(metrics.parse(before), metrics.parse(after))
        self.assertEqual(evidence['events']['high'], 2)
        self.assertEqual(evidence['events']['max'], 1)

    def test_missing_and_malformed_kernel_data_fail(self):
        """Missing telemetry, group-wide killing and malformed device rows cannot become zero evidence."""
        for field, value in (('memory.stat', 'anon 0\n'), ('memory.oom.group', '1\n'),
                             ('io.stat', '8:0 rbytes=1 rbytes=2\n'),
                             ('memory.current', '-1\n')):
            raw = snapshot()
            raw[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                metrics.parse(raw)
        raw = snapshot()
        del raw['memory.peak']
        with self.assertRaises(ValueError):
            metrics.parse(raw)

    def test_only_local_oom_evidence_classifies_sigkill(self):
        """Global/shared OOM observations or an unexplained kill do not establish local cap exhaustion."""
        evidence = dict(events=dict(max=0, oom=0, oom_kill=0))
        self.assertEqual(metrics.outcome(-9, evidence), 'signal-unclassified')
        for key in ('max', 'oom', 'oom_kill'):
            evidence['events'][key] = 1
        self.assertEqual(metrics.outcome(-9, evidence), 'local-cgroup-oom-kill')
        self.assertEqual(metrics.outcome(-6, evidence), 'signal-unclassified')
        self.assertEqual(metrics.outcome(0, evidence), 'completed')

    def test_counter_rollback_and_io_disappearance_fail(self):
        """Monotonic evidence cannot be silently clamped; new device activity starts at zero."""
        with self.assertRaises(ValueError):
            metrics.delta({'pgscan': 2}, {'pgscan': 1})
        with self.assertRaises(ValueError):
            metrics.delta({'rbytes': 1}, {})
        self.assertEqual(metrics.delta({}, {'rbytes': 4096}), {'rbytes': 4096})

    def test_cleanup_cannot_target_external_units(self):
        """Even valid-looking slices, parent services and malformed identifiers are refused before sudo."""
        for unit in ('system.slice', 'sshd.service', '../'+UNIT, UNIT+'; true',
                     'ragnarok-storage-pressure-.service'):
            with patch.object(scope.subprocess, 'run') as run, self.assertRaises(ValueError):
                scope.cleanup(unit)
            run.assert_not_called()

    def test_launch_is_bounded_and_stays_in_own_service(self):
        """Systemd controls apply to a fresh service, as the current user, with two independent timeouts."""
        argv = scope.launch_arguments(UNIT, '/tmp/result.json', 64*1024**2, 128*1024**2, 0,
                                      ['/tmp/native', 'open'])
        self.assertEqual(argv[:3], ['sudo', '-n', 'systemd-run'])
        for flag in ('--unit='+UNIT, '--property=MemoryHigh=67108864',
                     '--property=MemoryMax=134217728', '--property=MemorySwapMax=0',
                     '--property=OOMPolicy=continue', '--property=OOMScoreAdjust=-1000',
                     '--property=RuntimeMaxSec=45',
                     '--property=KillMode=control-group', '--collect'):
            self.assertIn(flag, argv)
        self.assertNotIn('set-property', argv)
        self.assertTrue(any(v.startswith('--setenv=LD_LIBRARY_PATH=') for v in argv))
        with self.assertRaises(ValueError):
            scope.launch_arguments(UNIT, '/tmp/result', 0, 1024**3, 0, ['probe'])

    def test_timeout_still_stops_owned_detached_unit(self):
        """Killing the outer process group cannot retire a systemd service; cleanup must run explicitly."""
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(scope.platform, 'system', return_value='Linux'), \
                patch.object(scope, 'command', side_effect=TimeoutError('observer timeout')), \
                patch.object(scope, 'cleanup', return_value={'state': 'inactive'}) as cleanup, \
                self.assertRaises(TimeoutError):
            scope.execute(['probe'], (67108864, 67108864, 0), folder, 'probe')
        cleanup.assert_called_once()
        scope.validate_unit(cleanup.call_args.args[0])

    def test_substituted_receipt_counter_is_rejected(self):
        """The original text, not a mutable summary, owns every attributed event and outcome."""
        raw = snapshot()
        evidence = metrics.derive(metrics.parse(raw), metrics.parse(raw))
        member = '0::/system.slice/'+UNIT+'\n'
        mounts = '29 23 0:26 / /sys/fs/cgroup rw - cgroup2 cgroup rw\n'
        report = dict(status='observed', unit=UNIT, initial_raw=raw,
                      observer_oom_score_adj_raw='-1000\n',
                      group='/sys/fs/cgroup/system.slice/'+UNIT, membership_raw=member,
                      mountinfo_raw=mounts, runs=[dict(before_raw=raw, after_raw=raw,
                      evidence=evidence, exit_code=0, outcome='completed', samples=1, timed_out=False,
                      sampled_peaks=dict(rss=4096, swap=0, anon=4096, file=0, cgroup_swap=0),
                      child_membership_raw=member, child_pid=17, child_identity_raw=json.dumps(dict(
                      membership_raw=member, oom_score_adj_raw='1000\n', pid=17)), resources=dict(peak_rss_bytes=4096,
                      minor_faults=1, major_faults=0, input_blocks=0, output_blocks=0))])
        scope.validate_receipt(report, UNIT, (67108864, 67108864, 0))
        altered = deepcopy(report)
        altered['runs'][0]['evidence']['events']['high'] = 100
        with self.assertRaises(ValueError):
            scope.validate_receipt(altered, UNIT, (67108864, 67108864, 0))

    def test_unsupported_host_cannot_claim_success(self):
        """Darwin is not a Linux pressure run; no command or privileged cleanup may be attempted."""
        with patch.object(scope.platform, 'system', return_value='Darwin'), \
                patch.object(scope, 'command') as command, self.assertRaises(RuntimeError):
            scope.execute(['probe'], (67108864, 67108864, 0), '/tmp', 'probe')
        command.assert_not_called()
