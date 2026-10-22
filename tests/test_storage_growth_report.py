# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independently authored sustained samples protect coverage, physical work and honest statistics."""
import copy
import sys
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from storage_growth_report import ENGINES,CASES,PHASES,METRICS,parse_growth,aggregate_growth,validate_growth,summarize_growth


def output(engine,count,steps,pattern='sweep'):
    """Authored complete observations include unavailable sentinels, not measurements from the native code."""
    rows=[]
    for sample in range(13):
        times=[(100+sample)*steps,-1 if engine=='memory' else 200+sample,
            -1 if engine=='journal' else 300+sample,-1 if engine=='journal' else 400+sample]
        metrics=[count*3+500,-1 if engine=='journal' else count*3+50,-1 if engine=='journal' else count*3,
            -1 if engine=='memory' else (0 if engine=='journal' else 1000),-1 if engine=='memory' else 2000,
            900 if engine=='managed' else -1,72 if engine=='managed' else -1]
        for revision in range(1,steps+1):
            rows.append('publication\t'+'\t'.join(map(str,[count,steps,pattern,sample,revision,100+sample]))+'\n')
        rows.append('growth\t' +'\t'.join(map(str,[count,steps,pattern,sample,*times,*metrics]))+'\n')
    return ''.join(rows)


def fixture():
    """Create complete reverse-order report evidence with independent exact median expectations."""
    passes=[{f'{e}-{n}-{s}-{p}':parse_growth(output(e,n,s,p),e,n,s,p) for e in order for n,s,p in CASES}
        for order in (ENGINES,tuple(reversed(ENGINES)))]
    return dict(status='checks-passed',schema_version=4,native_binary_sha256='a'*64,passes=passes,
        cases=aggregate_growth(passes),checks=[dict(exit_code=0,elapsed_seconds=0.01,log=f'{i}.log') for i in range(49)])


class StorageGrowthReportTests(unittest.TestCase):
    """Substituted, incomplete and failed measurements cannot become successful comparison panels."""

    def test_complete_raw_derived_panel(self):
        report=fixture();cases=validate_growth(report)
        self.assertEqual(len(cases),32)
        self.assertEqual(cases[0]['engines']['memory']['median_ns'],107.5*64)
        self.assertIn('Sustained storage workload',summarize_growth(report))
        self.assertIn('Strict disk reopen | — |',summarize_growth(report))

    def test_latency_tails_and_normalized_work_are_raw_derived(self):
        report=fixture();latency=report['cases'][0]['engines']['memory']['latency']
        self.assertEqual(latency['calls'],1280)
        self.assertEqual(latency['median_ns'],107.5)
        self.assertEqual(latency['p95_ns'],112)
        self.assertEqual(latency['max_ns'],112)
        self.assertEqual(latency['mean_call_ns'],107.5)
        self.assertAlmostEqual(latency['writes_per_second'],4e9/107.5)
        self.assertIn('correlated',summarize_growth(report))

    def test_latency_warmups_are_excluded_and_max_is_not_p95(self):
        report=fixture();rows=report['passes'][0]['memory-1024-64-sweep']
        rows[0]['publication_samples'][0]=1000000
        rows[0]['publication']+=1000000
        rows[-1]['publication_samples'][-1]=10000
        rows[-1]['publication']+=10000
        report['cases']=aggregate_growth(report['passes'])
        latency=report['cases'][0]['engines']['memory']['latency']
        self.assertEqual(latency['p95_ns'],112)
        self.assertEqual(latency['max_ns'],10000)
        self.assertEqual(latency['median_ns'],107.5)
        validate_growth(report)

    def test_exact_configuration_and_sample_coverage(self):
        raw=output('memory',1024,64)
        for bad in (raw.replace('1024','8192',1),raw.replace('\t64\t','\t256\t',1),raw+raw.splitlines()[0]+'\n',
                '\n'.join(raw.splitlines()[1:])+'\n',raw.replace('\t0\t','\t13\t',1),raw+'diagnostic\n'):
            with self.subTest(bad=bad[:45]),self.assertRaises(ValueError):
                parse_growth(bad,'memory',1024,64)

    def test_hot_observations_cannot_substitute_for_sweep(self):
        with self.assertRaises(ValueError):
            parse_growth(output('memory',1024,64,'hot'),'memory',1024,64,'sweep')

    def test_identical_first64_publications_have_identical_physical_work(self):
        report=fixture()
        for observations in report['passes']:
            for row in observations['managed-1024-64-hot']:
                row['stored_nodes']+=1
        with self.assertRaisesRegex(ValueError,'positive-control'):
            aggregate_growth(report['passes'])

    def test_complete_ordered_publication_witnesses(self):
        raw=output('memory',1024,64)
        lines=raw.splitlines()
        invalid=['\n'.join(lines[1:])+'\n',raw.replace('\t0\t1\t100','\t0\t2\t100',1),
            raw.replace('\t0\t1\t100','\t0\t1\t6401',1),raw+lines[0]+'\n']
        for bad in invalid:
            with self.subTest(bad=bad[:60]),self.assertRaises(ValueError):
                parse_growth(bad,'memory',1024,64)
        report=fixture();report['passes'][0]['memory-1024-64-sweep'][0]['publication_samples'][0]=True
        with self.assertRaises(ValueError):
            validate_growth(report)

    def test_bounded_canonical_values(self):
        raw=output('managed',1024,64)
        for replacement in ('0','-1',str(1<<63),'True','100.0','+100','0100'):
            with self.subTest(value=replacement),self.assertRaises(ValueError):
                parse_growth(raw.replace('\t6400\t','\t'+replacement+'\t',1),'managed',1024,64)

    def test_unavailable_operations_and_extents(self):
        for engine in ('memory','journal'):
            with self.subTest(engine=engine),self.assertRaises(ValueError):
                parse_growth(output(engine,1024,64).replace('\t-1\t','\t10\t',1),engine,1024,64)

    def test_physical_work_stays_identical(self):
        report=fixture();report['passes'][1]['managed-1024-64-sweep'][0]['stored_nodes']+=1
        with self.assertRaises(ValueError):
            aggregate_growth(report['passes'])

    def test_no_reordered_or_missing_backend(self):
        for reorder in (True,False):
            report=fixture();observations=report['passes'][0]
            if reorder:
                report['passes'][0]=dict(reversed(list(observations.items())))
            else:
                observations.pop('managed-1024-64-sweep')
            with self.assertRaises(ValueError):
                validate_growth(report)

    def test_structured_boolean_or_extra_field_refuses(self):
        for field,value in (('sample',False),('publication',True),('unexpected',1)):
            report=fixture();report['passes'][0]['memory-1024-64-sweep'][0][field]=value
            with self.assertRaises(ValueError):
                validate_growth(report)

    def test_forged_statistics_and_incomplete_native_evidence(self):
        for change in ('median','exit','log','binary','schema','status'):
            report=fixture()
            if change=='median': report['cases'][0]['engines']['memory']['median_ns']=1
            elif change=='exit': report['checks'][-1]['exit_code']=1
            elif change=='log': report['checks'][-1]['log']=report['checks'][0]['log']
            elif change=='binary': report['native_binary_sha256']='unbound'
            elif change=='schema': report['schema_version']=True
            else: report['status']='failed'
            with self.subTest(change=change),self.assertRaises(ValueError):
                summarize_growth(report)

    def test_raw_order_drift_is_visible(self):
        report=fixture()
        for row in report['passes'][1]['managed-1024-64-sweep']:
            row['publication']*=4
        report['cases']=aggregate_growth(report['passes'])
        self.assertTrue(report['cases'][0]['engines']['managed']['noisy'])
        self.assertTrue(report['cases'][0]['ratios']['managed']['unstable'])
        self.assertIn('‡',summarize_growth(report))


if __name__=='__main__':
    unittest.main()
