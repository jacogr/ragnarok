# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent SDK-count references enforce zero resident IO, strict reopen and real durable barriers."""
from contextlib import contextmanager
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import storage_growth_io as sdk
from storage_growth_report import ENGINES,CASES,unavailable
from storage_benchmark import atomic_text


def output(engine,count,steps,pattern):
    """Authored call patterns are independent of native timing and the production filesystem layout."""
    lines=[]
    for phase in sdk.IO_ORDER:
        if unavailable(engine,phase):
            continue
        counts={k:0 for k in sdk.OPERATIONS}
        if engine!='memory' and phase=='publication':
            counts.update(write=steps,fsync=steps*3)
        elif engine!='memory' and phase in ('reopen','retained_reopen','compacted_reopen'):
            counts.update(read=100,fsync=2 if engine=='journal' else 4,flock=1,close=2)
        elif engine=='managed' and phase in ('retention','maintenance'):
            counts.update(write=3,fsync=6,renameat=1,unlinkat=2,close=4)
        lines.append('io\t'+'\t'.join(map(str,(engine,count,steps,pattern,0,phase,*counts.values())))+'\n')
    return ''.join(lines)


def fixture():
    """Complete authored counter evidence carries a separate observed executable and object identity."""
    return dict(status='checks-passed',schema_version=1,profile=sdk.PROFILE,
        **{k:'d'*64 for k in sdk.SOURCE_FIELDS},observer_object_sha256='e'*64,native_binary_sha256='f'*64,
        observations={f'{e}-{n}-{s}-{p}':sdk.parse_io(output(e,n,s,p),e,n,s,p) for e in ENGINES for n,s,p in CASES},
        checks=[dict(exit_code=0,elapsed_seconds=0.01,log=f'io-check-{i}.log') for i in range(2+len(ENGINES)*len(CASES))])


@contextmanager
def native_stub(folder):
    """Leave all progress/artifact sequencing real while replacing only observer compilation/native execution."""
    obj=folder/'observer.o';obj.write_bytes(b'fixture SDK object')
    binary=folder/'binary';binary.write_bytes(b'fixture observed executable')
    def command(arguments,name,*args,**kwargs):
        executable,engine,count,steps,owned,samples,pattern=arguments
        assert samples==1
        log=folder/(name+'.log');log.write_text(output(engine,count,steps,pattern))
        return dict(exit_code=0,elapsed_seconds=0.01,log=str(log))
    with patch.object(sdk,'prepare',return_value=(obj,dict(source_sha256='d'*64,header_sha256='d'*64,
            build=dict(exit_code=0,elapsed_seconds=0.01,log='observer-build.log')))),patch.object(
            sdk.NativeChecks,'build',return_value=(dict(exit_code=0,elapsed_seconds=0.01,log='observed-build.log'),binary)),patch.object(
            sdk,'command',side_effect=command):
        yield


class StorageGrowthIoTests(unittest.TestCase):
    """Observed SDK counts supplement speed samples without ever becoming replacement timings."""

    def test_complete_counter_controls_and_summary(self):
        report=fixture();observations=sdk.validate_io(report)
        self.assertEqual(len(observations),3*len(CASES))
        self.assertIn('instrumented timings are discarded',sdk.summarize_io(report))
        self.assertIn('not device IO',sdk.summarize_io(report))

    def test_incomplete_duplicate_reordered_or_timing_output_refuses(self):
        raw=output('managed',1024,64,'sweep');lines=raw.splitlines()
        invalid=['\n'.join(lines[:-1])+'\n',raw+lines[0]+'\n','\n'.join([lines[1],lines[0],*lines[2:]])+'\n',
            raw+'growth\t1024\t64\tsweep\t0\n',raw.replace('\t1024\t','\t8192\t',1)]
        for bad in invalid:
            with self.subTest(output=bad[:50]),self.assertRaises(ValueError):
                sdk.parse_io(bad,'managed',1024,64,'sweep')

    def test_resident_memory_io_and_implicit_repair_refuse(self):
        report=fixture()
        for engine,phase,operation in [('memory','publication','read'),('journal','reads_before','read'),
                ('managed','snapshots','write'),('managed','reopen','ftruncate')]:
            bad=copy.deepcopy(report)
            row=next(r for r in bad['observations'][f'{engine}-1024-64-sweep'] if r['phase']==phase)
            row[operation]=1
            with self.subTest(engine=engine,phase=phase),self.assertRaises(ValueError):
                sdk.validate_io(bad)

    def test_barrier_and_lease_positive_witnesses_are_mandatory(self):
        for phase,operation in [('publication','fsync'),('publication','write'),('reopen','flock'),('reopen','fsync'),
                ('retention','renameat'),('maintenance','unlinkat')]:
            report=fixture();row=next(r for r in report['observations']['managed-1024-64-sweep'] if r['phase']==phase)
            row[operation]=0
            with self.subTest(phase=phase,operation=operation),self.assertRaises(ValueError):
                sdk.validate_io(report)

    def test_boolean_counter_failed_build_or_profile_cannot_pass(self):
        for field in ('counter','build','profile'):
            report=fixture()
            if field=='counter': report['observations']['memory-1024-64-sweep'][0]['read']=False
            elif field=='build': report['checks'][0]['exit_code']=False
            else: report['profile']='uninstrumented speed build'
            with self.subTest(field=field),self.assertRaises(ValueError):
                sdk.summarize_io(report)

    def test_complete_execution_publishes_counter_csv(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            with native_stub(folder):
                report=sdk.run_io('compiler','library',folder,atomic_text)
            sdk.validate_io(report)
            self.assertEqual(json.loads((folder/'results.json').read_text()),report)
            self.assertTrue((folder/'calls.csv').read_text().startswith('backend,items,publications'))

    def test_failed_native_rerun_clears_stale_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);(folder/'calls.csv').write_text('old success')
            with native_stub(folder),patch.object(sdk,'command',return_value=dict(exit_code=3,
                    elapsed_seconds=0.01,log='refused-control.log')) as run:
                with self.assertRaisesRegex(RuntimeError,'control failed'):
                    sdk.run_io('compiler','library',folder,atomic_text)
            self.assertEqual(run.call_count,1)
            self.assertFalse((folder/'calls.csv').exists())
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')

    def test_late_counter_csv_failure_refuses_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            def publish(path,value):
                if path.name=='calls.csv': raise OSError('counter CSV refused')
                atomic_text(path,value)
            with native_stub(folder),self.assertRaisesRegex(OSError,'counter CSV refused'):
                sdk.run_io('compiler','library',folder,publish)
            self.assertFalse((folder/'calls.csv').exists())
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')


if __name__=='__main__':
    unittest.main()
