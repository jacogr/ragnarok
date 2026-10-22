# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Drive real sustained artifact sequencing with authored native output and deterministic failures."""
from contextlib import contextmanager
import csv
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from test_storage_growth_report import output
import storage_growth
from storage_benchmark import atomic_text


@contextmanager
def native_stub(folder):
    """Keep orchestration/artifact publication real while substituting only native compilation/execution."""
    binary=folder/'binary';binary.write_bytes(b'checked sustained fixture')
    def command(arguments,name,*args,**kwargs):
        # Real logs carry every declared case and all thirteen independently authored observations.
        executable,engine,count,steps,owned,samples=arguments
        assert samples==13
        log=folder/(name+'.log');log.write_text(output(engine,count,steps))
        return dict(exit_code=0,elapsed_seconds=0.01,log=str(log))
    with patch.object(storage_growth.NativeChecks,'build',return_value=(dict(exit_code=0,
            elapsed_seconds=0.01,log=str(folder/'build.log')),binary)),patch.object(
            storage_growth,'command',side_effect=command):
        yield


class StorageGrowthExecutionTests(unittest.TestCase):
    """Failed child panels cannot retain successful raw artifacts or continue after a native refusal."""

    def test_complete_execution_and_csv(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            with native_stub(folder):
                report=storage_growth.run_growth('compiler','library',folder,atomic_text)
            self.assertEqual(report['status'],'checks-passed')
            self.assertEqual(len(report['checks']),25)
            rows=list(csv.DictReader(io.StringIO((folder/'samples.csv').read_text())))
            self.assertEqual(len(rows),312)
            self.assertEqual(sum(row['warmup']=='False' for row in rows),240)
            self.assertEqual(json.loads((folder/'results.json').read_text()),report)

    def test_build_refusal_stops_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            with native_stub(folder),patch.object(storage_growth.NativeChecks,'build',return_value=(
                    dict(exit_code=1,elapsed_seconds=0.01,log='refused.log'),folder/'binary')),patch.object(
                    storage_growth,'command') as run:
                with self.assertRaisesRegex(RuntimeError,'build failed'):
                    storage_growth.run_growth('compiler','library',folder,atomic_text)
            run.assert_not_called()
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')

    def test_failed_rerun_clears_previous_raw_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);(folder/'samples.csv').write_text('old success')
            (folder/'results.json').write_text('{"status":"checks-passed"}')
            with native_stub(folder),patch.object(storage_growth,'command',return_value=dict(
                    exit_code=7,elapsed_seconds=0.01,log='failed-native.log')) as run:
                with self.assertRaisesRegex(RuntimeError,'workload failed'):
                    storage_growth.run_growth('compiler','library',folder,atomic_text)
            self.assertEqual(run.call_count,1)
            self.assertFalse((folder/'samples.csv').exists())
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')

    def test_partial_native_output_is_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);log=folder/'partial.log';log.write_text('growth\t1024\t64\t0\n')
            with native_stub(folder),patch.object(storage_growth,'command',return_value=dict(
                    exit_code=0,elapsed_seconds=0.01,log=str(log))):
                with self.assertRaises(ValueError):
                    storage_growth.run_growth('compiler','library',folder,atomic_text)
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
            self.assertFalse((folder/'samples.csv').exists())

    def test_late_csv_failure_refuses_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            def publish(path,value):
                # Progress/failure JSON remains writable while final raw CSV publication is refused.
                if path.name=='samples.csv': raise OSError('CSV refused')
                atomic_text(path,value)
            with native_stub(folder),self.assertRaisesRegex(OSError,'CSV refused'):
                storage_growth.run_growth('compiler','library',folder,publish)
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
            self.assertFalse((folder/'samples.csv').exists())


if __name__=='__main__':
    unittest.main()
