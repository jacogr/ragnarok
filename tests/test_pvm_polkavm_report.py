# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Reject reference logs that hide sandbox CPU, fallback or incomplete guest checks."""
import unittest
from pvm_polkavm_report import parse, summarize


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

    def test_missing_engine_pair_cannot_supply_ratio(self):
        native=parse(log(),'compiler','minimal',1000)
        with self.assertRaises(ValueError):summarize([dict(pair=0,backend='compiler',cases=native)])


if __name__=='__main__':unittest.main()
