# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect equal storage workload coverage, honest durability comparisons and failed-run evidence."""
from contextlib import contextmanager
import copy
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from storage_benchmark_report import ENGINES,COUNTS,TOPOLOGIES,VALUE_BYTES,BATCH_WIDTHS,CASES,PHASES,METRICS,parse_output,aggregate,summarize_benchmark
from summarize_tests import summarize


# Authored complete sample grids isolate report correctness from machine-dependent timing values.
def output(engine,count,topology='leading',value_bytes=256,batch_width=1):
    # Unsupported reopen/reclamation operations remain explicit sentinels in otherwise complete samples.
    return ''.join(f'sample\t{count}\t{topology}\t{value_bytes}\t{batch_width}\t{s}\t'+
        '\t'.join(map(str,[100+s,200+s,300+s,-1 if engine=='memory' else 400+s,
                           -1 if engine=='journal' else 500+s,-1 if engine=='journal' else 600+s,700+s,800+s,count*3+100,count*3,
            -1 if engine=='memory' else (0 if engine=='journal' else 100),
            -1 if engine=='memory' else 200,90 if engine=='managed' else -1,72 if engine=='managed' else -1]))+'\n' for s in range(13))


def passes():
    """Build two complete identical passes whose statistics have independent exact expectations."""
    one={f'{e}-{n}-{t}-{v}-{w}':parse_output(output(e,n,t,v,w),e,n,t,v,w) for e in ENGINES for n,t,v,w in CASES}
    return [one,copy.deepcopy(one)]


@contextmanager
def native_stub(folder):
    """Generate authored raw evidence while leaving artifact/error sequencing real."""
    import storage_benchmark
    library=folder/'crypto/library'
    library.parent.mkdir()
    library.write_bytes(b'fixture native ABI')
    def command(arguments,name,*args,**kwargs):
        # Each declared identity gets a complete independently authored native output log.
        binary,engine,count,directory,topology,value_bytes,batch_width=arguments
        log=folder/(name+'.log')
        log.write_text(output(engine,int(count),topology,int(value_bytes),int(batch_width)))
        return dict(exit_code=0,log=str(log),elapsed_seconds=0.001)
    with patch.object(storage_benchmark,'BUILD',folder),patch.object(
            storage_benchmark,'installed',return_value=(folder/'compiler',{})),patch.object(
            storage_benchmark,'crypto_sources',return_value={}),patch.object(
            storage_benchmark,'build_crypto',return_value=library),patch.object(
            storage_benchmark,'cpu_model',return_value='fixture CPU'),patch.object(
            storage_benchmark.NativeChecks,'build',return_value=(
                dict(exit_code=0,log='native-build.log',elapsed_seconds=0.001),folder/'binary')),patch.object(
            storage_benchmark,'command',side_effect=command):
        yield storage_benchmark


class StorageBenchmarkTests(unittest.TestCase):
    """Partial or substituted observations must never become published speed comparisons."""

    def test_complete_table_and_no_memory_reopen(self):
        report=dict(status='checks-passed',passes=passes())
        report['cases']=aggregate(report['passes'])
        text=summarize(report,'storage-benchmark')
        self.assertIn('Storage speed comparison',text)
        self.assertIn('| Memory | Journal | Managed |',text)
        self.assertIn('Strict disk reopen | — |',text)
        self.assertIn('memory publication is not durable',text)
        self.assertIn('warm resident',text)
        self.assertEqual(len(report['cases']),128)
        self.assertEqual(report['cases'][0]['engines']['memory']['median_ns'],107.5)

    def test_missing_duplicate_or_wrong_sample(self):
        raw=output('memory',1024)
        invalid=[raw.rsplit('\n',2)[0]+'\n',raw+raw.splitlines()[0]+'\n',
                 raw.replace('sample\t1024\tleading\t256\t1\t0','sample\t8192\tleading\t256\t1\t0'),
                 raw.replace('sample\t1024\tleading\t256\t1\t0','sample\t1024\tleading\t256\t1\t13'),raw+'diagnostic\n']
        for bad in invalid:
            with self.subTest(output=bad[:70]),self.assertRaises(ValueError):
                parse_output(bad,'memory',1024)

    def test_key_topology_identity_is_required(self):
        """A fast run of one shape cannot substitute for the other key-routing workload."""
        with self.assertRaises(ValueError):
            parse_output(output('memory',1024,'trailing'),'memory',1024,'leading')
        raw=passes()
        raw[0]['memory-1024-trailing-256-1']=raw[0]['memory-1024-leading-256-1']
        with self.assertRaises(ValueError):
            aggregate(raw)
        # Aggregation also requires all declared case keys.
        del raw[0]['memory-1024-leading-256-1']
        with self.assertRaises(ValueError):
            aggregate(raw)

    def test_value_representation_identity_is_required(self):
        """Inline-value observations cannot substitute for the out-of-line payload workload."""
        with self.assertRaises(ValueError):
            parse_output(output('memory',1024,value_bytes=16),'memory',1024,value_bytes=256)
        raw=passes()
        raw[0]['memory-1024-leading-256-1']=raw[0]['memory-1024-leading-16-1']
        with self.assertRaises(ValueError):
            aggregate(raw)

    def test_publication_batch_identity_is_required(self):
        """A one-write timing cannot substitute for a four-write publication workload."""
        with self.assertRaises(ValueError):
            parse_output(output('memory',1024,batch_width=4),'memory',1024,batch_width=1)
        raw=passes()
        raw[0]['memory-1024-leading-256-4']=raw[0]['memory-1024-leading-256-1']
        with self.assertRaises(ValueError):
            aggregate(raw)

    def test_positive_bounded_durations_and_explicit_reopen(self):
        raw=output('memory',1024)
        for old,new in [('\t100\t','\t0\t'),('\t100\t','\t-2\t'),
                        ('\t100\t','\t'+str(1<<63)+'\t'),('\t-1\t','\t10\t')]:
            with self.subTest(new=new),self.assertRaises(ValueError):
                parse_output(raw.replace(old,new),'memory',1024)
        with self.assertRaises(ValueError):
            parse_output(output('journal',1024).replace('\t400\t','\t-1\t'),'journal',1024)

    def test_no_fabricated_reclamation_for_journal(self):
        """Neither reclamation mode can acquire a fabricated positive journal timing."""
        for phase in ('maintenance','retention'):
            for engine,invalid in [('journal','500'),('managed','-1')]:
                lines=[line.split('\t') for line in output(engine,1024).splitlines()]
                lines[0][6+PHASES.index(phase)]=invalid
                with self.subTest(phase=phase,engine=engine),self.assertRaises(ValueError):
                    parse_output('\n'.join('\t'.join(line) for line in lines)+'\n',engine,1024)

    def test_physical_metadata_is_bounded_and_stable(self):
        """Impossible extents or changing fixture sizes cannot annotate a successful comparison."""
        lines=[line.split('\t') for line in output('managed',1024).splitlines()]
        for metric,invalid in [('selected_nodes','0'),('snapshot_bytes','-1')]:
            bad=copy.deepcopy(lines)
            bad[0][6+len(PHASES)+METRICS.index(metric)]=invalid
            with self.subTest(metric=metric),self.assertRaises(ValueError):
                parse_output('\n'.join('\t'.join(row) for row in bad)+'\n','managed',1024)
        raw=passes()
        raw[0]['managed-1024-leading-256-1'][0]['stored_nodes']+=1
        with self.assertRaises(ValueError):
            aggregate(raw)

    def test_missing_backend_pass_or_forged_statistic(self):
        raw=passes()
        with self.assertRaises(ValueError):aggregate(raw[:1])
        del raw[0]['managed-8192-trailing-256-1']
        with self.assertRaises(ValueError):aggregate(raw)
        report=dict(status='checks-passed',passes=passes())
        report['cases']=aggregate(report['passes'])
        report['cases'][0]['engines']['memory']['median_ns']=1
        with self.assertRaises(ValueError):summarize_benchmark(report)

    def test_failure_does_not_show_old_table(self):
        text=summarize_benchmark(dict(status='failed',error='native assertion',cases=[dict(old=True)]))
        self.assertIn('Status: failed',text)
        self.assertNotIn('| Entries |',text)
        self.assertIn('native assertion',text)

    def test_missing_report_summary_is_visible_and_fails(self):
        """The setup-free Actions summary must expose setup failure instead of rendering success."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            result=subprocess.run([sys.executable,str(ROOT/'tools/summarize_tests.py'),
                '--kind','storage-benchmark','--report',str(folder/'missing.json'),
                '--output',str(folder/'step.md'),'--artifact',str(folder/'summary.md')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('No usable verification report',(folder/'step.md').read_text())
            self.assertEqual((folder/'step.md').read_text(),(folder/'summary.md').read_text())

    def test_builds_missing_crypto_before_native_benchmark(self):
        """A fresh build must hash/link the newly built library rather than require a previous consumer."""
        import storage_benchmark
        import hashlib
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            library=folder/'crypto/library'
            paths={'fixture':'pinned sources'}
            def build_crypto(selected):
                # The only provider creates the previously absent ABI, just as a fresh CI build must.
                self.assertEqual(selected,paths)
                self.assertFalse(library.exists())
                library.parent.mkdir()
                library.write_bytes(b'fresh crypto ABI')
                return library
            def native_build(compiler,source,name,**options):
                # Stop after the build boundary: application workloads remain covered by the real benchmark.
                self.assertEqual(options['crypto_library'],library)
                self.assertEqual(library.read_bytes(),b'fresh crypto ABI')
                return dict(exit_code=1,log='native-build.log',output='deliberate native failure'),folder/'binary'
            with patch.object(storage_benchmark,'BUILD',folder),patch.object(
                    storage_benchmark,'installed',return_value=(folder/'compiler',{})),patch.object(
                    storage_benchmark,'crypto_sources',return_value=paths) as sources,patch.object(
                    storage_benchmark,'build_crypto',side_effect=build_crypto) as crypto,patch.object(
                    storage_benchmark.NativeChecks,'build',side_effect=native_build) as native:
                with self.assertRaisesRegex(RuntimeError,'Storage benchmark build failed'):
                    storage_benchmark.run()
            sources.assert_called_once_with(False)
            crypto.assert_called_once_with(paths)
            native.assert_called_once()
            report=json.loads((folder/'results.json').read_text())
            self.assertEqual(report['crypto_sha256'],hashlib.sha256(library.read_bytes()).hexdigest())
            self.assertEqual(report['status'],'failed')
            self.assertIn('Storage benchmark build failed',report['error'])

    def test_complete_native_stub_publishes_all_artifacts(self):
        """Success follows complete raw CSV and validated Markdown publication."""
        import csv
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            with native_stub(folder) as runner,patch('builtins.print'):
                runner.run()
            report=json.loads((folder/'results.json').read_text())
            self.assertEqual(report['status'],'checks-passed')
            with (folder/'samples.csv').open() as source:
                rows=list(csv.reader(source))
            self.assertEqual(len(rows),1+2*len(ENGINES)*len(CASES)*13)
            self.assertEqual((folder/'summary.md').read_text(),summarize_benchmark(report))
            self.assertFalse(list(folder.glob('.*.tmp')))

    def test_csv_and_summary_failures_cannot_publish_success(self):
        """Late write/render refusal removes final CSV and records a failed diagnostic summary."""
        for boundary in ('csv','summary','replace'):
            with self.subTest(boundary=boundary),tempfile.TemporaryDirectory() as temporary:
                folder=Path(temporary)
                with native_stub(folder) as runner,patch('builtins.print'):
                    original_summary=runner.summarize_benchmark
                    original_replace=runner.os.replace
                    def summary(report):
                        # Success-only failure still permits the failed-run diagnostic.
                        if report['status']=='checks-passed':
                            raise ValueError('summary refused')
                        return original_summary(report)
                    def replace(source,target):
                        # Progress/failure JSON remains writable when CSV publication fails.
                        if Path(target).name=='samples.csv':
                            raise OSError('replace refused')
                        return original_replace(source,target)
                    if boundary=='csv':
                        selected=patch.object(runner.csv,'writer',side_effect=RuntimeError('csv refused'))
                    elif boundary=='summary':
                        selected=patch.object(runner,'summarize_benchmark',side_effect=summary)
                    else:
                        selected=patch.object(runner.os,'replace',side_effect=replace)
                    with selected,self.assertRaisesRegex(Exception,boundary+' refused'):
                        runner.run()
                self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
                self.assertFalse((folder/'samples.csv').exists())
                self.assertIn('Status: failed',(folder/'summary.md').read_text())
                self.assertFalse(list(folder.glob('.*.tmp')))

    def test_failed_rerun_removes_stale_success(self):
        import storage_benchmark
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            for name in ('summary.md','samples.csv','results.json'):
                (folder/name).write_text('old successful data')
            with patch.object(storage_benchmark,'BUILD',folder),patch.object(
                    storage_benchmark,'installed',side_effect=RuntimeError('setup refused')):
                with self.assertRaisesRegex(RuntimeError,'setup refused'):
                    storage_benchmark.run()
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
            self.assertIn('Status: failed',(folder/'summary.md').read_text())
            self.assertFalse((folder/'samples.csv').exists())
            self.assertNotIn('old successful',(folder/'summary.md').read_text())


# Discovery imports only inert tests; the standalone entry never provisions native dependencies.
if __name__=='__main__':
    unittest.main(verbosity=2)
