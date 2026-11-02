# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Reject reference logs that hide sandbox CPU, fallback or incomplete guest checks."""
import unittest
import tempfile
import json
from pathlib import Path
from unittest.mock import patch
from pvm_polkavm_report import parse, summarize, parse_clock_control


def log(backend='compiler'):
    """Independent literal counters retain one complete, actually selected guest process."""
    lines=[f'REFERENCE_MODULE,guest,{backend},{backend},{80 if backend=="compiler" else 0},500',
           'GUEST,minimal']
    for i in range(13):
        parent,worker=(10,90) if backend=='compiler' else (1000,0)
        lines += [f'REFERENCE_CPU,minimal-1000,{i},{parent},{worker},{parent+worker},{int(backend=="compiler")}',
                  f'SIEVE,polkavm_{backend},1000,{i},2000,{parent+worker}']
    return '\n'.join(lines)+'\n'


class ReferenceReportTests(unittest.TestCase):
    """The report must represent complete guest CPU rather than only the waiting parent."""
    def test_compiler_worker_and_interpreter_are_separate(self):
        native=parse(log(),'compiler','minimal',1000)['minimal-1000']
        interpreted=parse(log('interpreter'),'interpreter','minimal',1000)['minimal-1000']
        self.assertEqual(native['warm_cpu_ns'],100)
        self.assertEqual(interpreted['warm_cpu_ns'],1000)
        summary=summarize([dict(pair=0,backend='compiler',cases={'minimal-1000':native}),
                           dict(pair=0,backend='interpreter',cases={'minimal-1000':interpreted})])
        self.assertEqual(summary['minimal-1000']['native_per_interpreted'],0.1)

    def test_parent_only_and_double_counted_cpu_rejected(self):
        for bad in (log().replace(',10,90,100,1',',10,0,10,0'),
                    log().replace(',10,90,100,1',',10,90,190,1')):
            with self.subTest(output=bad[:100]),self.assertRaises(ValueError):parse(bad,'compiler','minimal',1000)

    def test_compiler_substitution_or_missing_code_rejected(self):
        for bad in (log().replace('compiler,compiler,80','compiler,interpreter,80'),
                    log().replace('compiler,compiler,80','compiler,compiler,0')):
            with self.assertRaises(ValueError):parse(bad,'compiler','minimal',1000)

    def test_incomplete_duplicate_and_unvalidated_samples_rejected(self):
        source=log().splitlines()
        for rows in (source[:-2],source+[source[-1]],source[:-1],
                     [source[2],*source[:2],*source[3:]],
                     source+['unavailable\t0\tcompiler refused']):
            with self.assertRaises(ValueError):parse('\n'.join(rows),'compiler','minimal',1000)

    def test_foreign_guest_and_counter_disagreement_rejected(self):
        for bad in (log().replace('GUEST,minimal','GUEST,memset'),
                    log().replace('2000,100','2000,101')):
            with self.assertRaises(ValueError):parse(bad,'compiler','minimal',1000)

    def test_duplicate_backend_cannot_replace_observation(self):
        cases=parse(log(),'compiler','minimal',1000)
        row=dict(pair=0,backend='compiler',cases=cases)
        with self.assertRaises(ValueError):summarize([row,row])

    def test_task_cpu_control_agrees_with_child_self_cpu(self):
        observed='REFERENCE_CLOCK_CONTROL,14375,20093166,20107541,20010583\n'
        self.assertEqual(parse_clock_control(observed)['worker'],20093166)
        for changed in ('REFERENCE_CLOCK_CONTROL,14375,0,14375,20010583',
                        'REFERENCE_CLOCK_CONTROL,14375,20093166,40186332,20010583',
                        'REFERENCE_CLOCK_CONTROL,14375,40000000,40014375,20010583',
                        observed+'unexpected output',observed.replace('20010583','-1')):
            with self.subTest(changed=changed),self.assertRaises(ValueError):parse_clock_control(changed)

    def test_invalid_pair_request_clears_stale_success(self):
        """Both bad numeric choices and malformed text must invalidate an earlier JSON verdict."""
        import pvm_polkavm_compare as comparison
        for value in ('3','invalid'):
            with self.subTest(value=value),tempfile.TemporaryDirectory() as folder:
                base=Path(folder)
                (base/'results.json').write_text(json.dumps(dict(status='checks-passed',head='old')))
                (base/'summary.md').write_text('old success')
                with patch.object(comparison,'BUILD',base), \
                     patch.object(comparison.platform,'system',return_value='Linux'), \
                     patch.object(comparison.platform,'machine',return_value='x86_64'), \
                     patch.dict('os.environ',{'PVM_POLKAVM_PAIRS':value}), \
                     patch.object(comparison,'NativeChecks',side_effect=AssertionError('unexpected native work')):
                    with self.assertRaises(ValueError):comparison.run()
                result=json.loads((base/'results.json').read_text())
                self.assertEqual(result['status'],'failed')
                self.assertNotIn('head',result)
                self.assertFalse((base/'summary.md').exists())

    def test_one_call_availability_control_requires_worker_cpu(self):
        """The native engine must really run once before testing its error path."""
        source='\n'.join(log().splitlines()[:4])+'\n'
        self.assertEqual(len(parse(source,'compiler','minimal',1000,count=1)['minimal-1000']['samples']),1)
        with self.assertRaises(ValueError):parse(source.replace(',10,90,100,1',',10,0,10,0'),'compiler','minimal',1000,count=1)

    def test_missing_engine_pair_cannot_supply_ratio(self):
        native=parse(log(),'compiler','minimal',1000)
        with self.assertRaises(ValueError):summarize([dict(pair=0,backend='compiler',cases=native)])


if __name__=='__main__':unittest.main()
