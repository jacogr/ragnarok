# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect equal storage workload coverage, honest durability comparisons and failed-run evidence."""
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
from storage_benchmark_report import ENGINES,COUNTS,TOPOLOGIES,CASES,PHASES,parse_output,aggregate,summarize_benchmark
from summarize_tests import summarize


# Authored complete sample grids isolate report correctness from machine-dependent timing values.
def output(engine,count,topology='leading'):
    return ''.join(f'sample\t{count}\t{topology}\t{s}\t{100+s}\t{200+s}\t{300+s}\t'+
                   str(-1 if engine=='memory' else 400+s)+'\n' for s in range(13))


def passes():
    """Build two complete identical passes whose statistics have independent exact expectations."""
    one={f'{e}-{n}-{t}':parse_output(output(e,n,t),e,n,t) for e in ENGINES for n,t in CASES}
    return [one,copy.deepcopy(one)]


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
        self.assertEqual(len(report['cases']),16)
        self.assertEqual(report['cases'][0]['engines']['memory']['median_ns'],107.5)

    def test_missing_duplicate_or_wrong_sample(self):
        raw=output('memory',1024)
        invalid=[raw.rsplit('\n',2)[0]+'\n',raw+raw.splitlines()[0]+'\n',
                 raw.replace('sample\t1024\tleading\t0','sample\t8192\tleading\t0'),
                 raw.replace('sample\t1024\tleading\t0','sample\t1024\tleading\t13'),raw+'diagnostic\n']
        for bad in invalid:
            with self.subTest(output=bad[:70]),self.assertRaises(ValueError):
                parse_output(bad,'memory',1024)

    def test_key_topology_identity_is_required(self):
        """A fast run of one shape cannot substitute for the other key-routing workload."""
        with self.assertRaises(ValueError):
            parse_output(output('memory',1024,'trailing'),'memory',1024,'leading')
        raw=passes()
        raw[0]['memory-1024-trailing']=raw[0]['memory-1024-leading']
        with self.assertRaises(ValueError):
            aggregate(raw)
        # Aggregation also requires all declared case keys.
        del raw[0]['memory-1024-leading']
        with self.assertRaises(ValueError):
            aggregate(raw)

    def test_positive_bounded_durations_and_explicit_reopen(self):
        raw=output('memory',1024)
        for old,new in [('\t100\t','\t0\t'),('\t100\t','\t-2\t'),
                        ('\t100\t','\t'+str(1<<63)+'\t'),('\t-1\n','\t10\n')]:
            with self.subTest(new=new),self.assertRaises(ValueError):
                parse_output(raw.replace(old,new),'memory',1024)
        with self.assertRaises(ValueError):
            parse_output(output('journal',1024).replace('\t400\n','\t-1\n'),'journal',1024)

    def test_missing_backend_pass_or_forged_statistic(self):
        raw=passes()
        with self.assertRaises(ValueError):aggregate(raw[:1])
        del raw[0]['managed-8192-trailing']
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
