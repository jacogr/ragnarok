# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect isolated resource accounting, complete native controls and failure artifact retirement."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import storage_resources as resources
from storage_growth_report import parse_growth, METRICS
from test_storage_growth_report import output, build_command


def fixture():
    """Author complete process evidence independently of the runner's orchestration."""
    binary = '/fixture/resources-native'
    report = dict(status='checks-passed', schema_version=1, profile=resources.PROFILE,
                  policy=resources.POLICY, native_binary_sha256='a'*64,
                  python_executable=sys.executable, observations=[],
                  inputs=dict(head='a'*40, dirty=False, compiler_sha256='b'*64, clang='fixture clang', toolchain={},
                    native_components={k: 'c'*64 for k in ('bridge', 'provider_loader', 'provider_build')},
                    sources={str(p.relative_to(ROOT)): 'd'*64 for p in
                        [*resources.benchmark_sources(), ROOT/'tools/storage_resources.py', resources.CHILD]}),
                  hardware=dict(platform='fixture', cpu='fixture', machine='fixture', page_size_bytes=4096),
                  checks=[dict(exit_code=0, elapsed_seconds=1, log='build.log', command=build_command(binary))])
    report['checks'][0]['command'][-1] = str(resources.SOURCE)
    for index, order in enumerate((resources.ENGINES, tuple(reversed(resources.ENGINES)))):
        for engine in order:
            for count in resources.CASES:
                row = parse_growth(output(engine, count, 64), engine, count, 64)[0]
                report['observations'].append(dict({'pass': index}, backend=engine, items=count,
                    publications=64, pattern='sweep', physical={k: row[k] for k in METRICS},
                    resources=dict(peak_rss_bytes=123456, minor_faults=9, major_faults=0)))
                report['checks'].append(dict(exit_code=0, elapsed_seconds=1,
                    log=f'{index}-{engine}-{count}.log', command=[sys.executable, str(resources.CHILD),
                    '/fixture/counters.json', binary, engine, str(count), '64', '/fixture/owned', '1', 'sweep']))
    return report


class StorageResourceTests(unittest.TestCase):
    """Counter integrity, isolated real execution and native failure remain observable requirements."""

    def test_complete_opposite_order_report(self):
        """Every backend and extent has two observations with independently retained physical controls."""
        report = fixture()
        self.assertEqual(len(resources.validate(report)), 12)
        self.assertIn('whole native process', resources.summarize(report))
        self.assertNotIn('speedup', resources.summarize(report))


    def test_tampered_counters_commands_and_provenance_refuse(self):
        """Malformed units, boolean values, missing cases, unchecked builds and changed physical work refuse."""
        mutations = [lambda r: r['observations'].pop(),
                     lambda r: r['observations'].reverse(),
                     lambda r: r['observations'][0]['resources'].update(peak_rss_bytes=True),
                     lambda r: r['observations'][0]['resources'].update(major_faults=-1),
                     lambda r: r['observations'][0]['resources'].update(minor_faults=1<<63),
                     lambda r: r['observations'][0].update(publication_ns=1),
                     lambda r: r['observations'][-1]['physical'].update(stored_nodes=1),
                     lambda r: r['checks'][1].update(exit_code=124),
                     lambda r: r['checks'][1]['command'].__setitem__(8, '13'),
                     lambda r: r['checks'][0]['command'].insert(-1, '--mm:refc'),
                     lambda r: r['checks'][0]['command'].insert(-1, '--assertions:off'),
                     lambda r: r['inputs']['sources'].pop('tools/storage_resource_child.py'),
                     lambda r: r['inputs']['native_components'].update(provider_build='e'*64),
                     lambda r: r.update(status='running')]
        for change in mutations:
            with self.subTest(change=mutations.index(change)):
                report = copy.deepcopy(fixture()); change(report)
                with self.assertRaises(ValueError):
                    resources.validate(report)



    def test_failed_build_retires_success_artifacts(self):
        """The public runner retains failed build evidence and removes its previous successful summary."""
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder); (target/'summary.md').write_text('stale success')
            with patch.object(resources, 'BUILD', target), patch.object(resources, 'installed', return_value=('compiler', None)), patch.object(
                    resources, 'dependencies'), patch.object(resources, 'build_native'), patch.object(resources, 'identity', return_value={}), patch.object(
                    resources, 'cpu_model', return_value='fixture'), patch.object(resources.NativeChecks, 'build', return_value=(
                        dict(exit_code=1, log='failed build', command=[]), target/'absent')):
                with self.assertRaisesRegex(RuntimeError, 'build failed'):
                    resources.run()
            self.assertFalse((target/'summary.md').exists())
            self.assertEqual(json.loads((target/'results.json').read_text())['status'], 'failed')
