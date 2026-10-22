# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Boundary witnesses for child-local memory experiment tooling."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import json
import platform
import resource
import subprocess
import tempfile
from unittest.mock import patch
import storage_limit_collect as collector
from storage_limit_report_fixtures import fixture
from storage_limit_receipts import validate_probe
from storage_limit_budget import CAPS
from storage_limit_probe import __file__ as PROBE

class LimitIntegrationTests(unittest.TestCase):
    """Exercise the host probe and the orchestration boundary around unchanged native controls."""
    def test_real_disposable_host_probe(self):
        """Only the probe subprocess changes limits; the Python discovery process remains uncapped."""
        inherited=resource.getrlimit(resource.RLIMIT_AS)
        result=subprocess.run([sys.executable,PROBE,str(CAPS[0])],capture_output=True,text=True,check=True,timeout=10)
        self.assertEqual(resource.getrlimit(resource.RLIMIT_AS),inherited)
        observed=validate_probe(json.loads(result.stdout),CAPS[0])
        if platform.system()=='Darwin':
            self.assertEqual(observed['limit']['status'],'unsupported')
        else:
            self.assertEqual(observed['limit']['system'],'Linux')
    def collect_fixture(self,system='Linux',changed=False,final_failure=False):
        """Mock native application calls only; the real collector must preserve phase and failure sequencing."""
        source=fixture(system);calls=[]
        def command(args,name,folder,timeout):
            """Producer logs bind the authored root; probe logs use independently authored raw receipts."""
            argv=[str(a) for a in args];log=Path(folder)/(name+'.log')
            if name.startswith('probe-'):
                probe=next(p for p in source['probes'] if p['cap']==int(argv[-1]));raw=probe['raw']
            else:
                case=next(r for r in source['rows'] if r['case']==[argv[2],int(argv[3])]);raw=case['prepared_raw']
            log.write_text(raw)
            return dict(command=argv,log=str(log),exit_code=0,elapsed_seconds=0.01)
        def execute(args,cap,owned,folder,name):
            """Record real collector intent and return native raw controls/refusal witnesses from the fixture."""
            calls.append((name,cap))
            row=next(r for r in source['rows'] if r['case']==[args[2],int(args[3])])
            attempt=next(a for a in row['attempts'] if a['name']==name.split('-')[-1])
            execution=attempt['execution']
            if final_failure and name.endswith('-after'):
                execution=dict(execution,outcome='nonzero-exit')
            return execution
        reads=0
        def fingerprint(path,backend):
            """A byte change after a child must abort instead of becoming an observed refusal."""
            nonlocal reads
            reads+=1;expected=next(r['selected'] for r in source['rows'] if r['case'][0]==backend)
            return {k:('f'*64 if changed and reads>1 else v) for k,v in expected.items()}
        with tempfile.TemporaryDirectory() as folder:
            fake_build=dict(exit_code=0,command=[],log='build.log')
            with patch.object(collector,'installed',return_value=('compiler',None)),patch.object(collector,'dependencies'),patch.object(collector,'build_native'),patch.object(collector.NativeChecks,'build',return_value=(fake_build,Path('/fixture/panel-native'))),patch.object(collector,'identity',return_value=source['identity']),patch.object(collector,'snapshot',return_value=source['context_before']),patch.object(collector,'command',side_effect=command),patch.object(collector,'execute',side_effect=execute),patch.object(collector,'fingerprint',side_effect=fingerprint):
                result=collector.collect(folder)
        return result,calls
    def test_refusals_keep_both_native_controls(self):
        """Signalled/nonzero capped children still receive the final exact-map control."""
        report,calls=self.collect_fixture()
        self.assertEqual(report['status'],'collected');self.assertEqual(len(calls),20)
        for row in report['rows']:
            self.assertEqual(row['attempts'][-1]['outcome'],'completed')
    def test_unavailable_caps_never_start_native_children(self):
        """Darwin keeps all twelve unavailable rows while executing only eight uncapped controls."""
        report,calls=self.collect_fixture('Darwin')
        self.assertEqual(len(calls),8);self.assertTrue(all(cap is None for name,cap in calls))
        self.assertEqual(sum(a['outcome']=='unavailable' for r in report['rows'] for a in r['attempts']),12)
    def test_mutation_and_final_control_failure_abort(self):
        """Neither changed bytes nor a failed post-refusal control can publish a complete report."""
        with self.assertRaisesRegex(ValueError,'changed selected bytes'):
            self.collect_fixture(changed=True)
        with self.assertRaisesRegex(RuntimeError,'control or admitted limit failed'):
            self.collect_fixture(final_failure=True)
