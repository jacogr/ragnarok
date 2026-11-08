# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check CI cache isolation, invalidation and optional dependency reuse."""
from pathlib import Path
import re
import unittest

from workflow_fixtures import event_context, selected_families, selected_steps, workflow

ROOT = Path(__file__).resolve().parents[1]


class DownloadCacheTests(unittest.TestCase):
    """Keep cache failures separate from verification and exclude application/secret trees."""

    def test_every_host_job_restores_downloads_before_work(self):
        """Cold setup and verification must remain scheduled independently of cache hits."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        for job_id, job in workflow(text)['jobs'].items():
            families = selected_families(text, job_id, event_context()) or [{}]
            for family in families:
                steps = selected_steps(job, family, event_context())
                caches = [step for step in steps if step.get('uses', '').startswith('actions/cache@')]
                if family.get('group') == 'docker':
                    self.assertEqual(caches, [], 'Host downloads must not enter Docker setup')
                    continue
                self.assertTrue(caches, (job_id, family))
                commands = [step for step in steps if step.get('run', '').startswith('make ')]
                self.assertTrue(commands)
                self.assertLess(max(steps.index(step) for step in caches), steps.index(commands[0]))
                for step in commands:
                    self.assertNotIn('cache-hit', step.get('if', ''), step)

    def test_cache_payloads_exclude_credentials_application_outputs_and_evidence(self):
        """Only public dependencies and validated dependency outputs may be uploaded from a runner."""
        allowed = {'build-tools/toolchain/*.archive', 'build-tools/model-tools/*.archive',
                   '~/.cargo/registry/index', '~/.cargo/registry/cache', '~/.cargo/git/db',
                   'build-tools/model-tools/bin/tlanif', 'build-tools/model-tools/environment.json',
                   'build-tools/bandersnatch/native-environment.json',
                   'build-tools/bandersnatch/target/release',
                   'build-tools/crypto/native-environment.json', 'build-tools/crypto/*.so',
                   'build-tools/crypto/*.dylib', 'build-tools/quic/native-environment.json',
                   'build-tools/quic/*.so', 'build-tools/quic/*.dylib',
                   'build-tools/polkavm/native-environment.json', 'build-tools/polkavm/release'}
        jobs = workflow((ROOT/'.github/workflows/ci.yml').read_text())['jobs']
        for job in jobs.values():
            for step in job['steps']:
                if not step.get('uses', '').startswith('actions/cache@'):
                    continue
                paths = set(step['with']['path'].splitlines())
                self.assertTrue(paths and paths <= allowed, paths)
                self.assertTrue(step.get('continue-on-error'), 'Cache service failure must allow setup')
                self.assertFalse(step['with'].get('fail-on-cache-miss', False))
                self.assertFalse(step['with'].get('restore-keys'), 'Use only the matching pin set')
                self.assertRegex(step['uses'], r'@[0-9a-f]{40}$')

    def test_cache_keys_separate_hosts_and_change_with_dependency_pins(self):
        """Cross-platform restores and unchanged keys after pin updates waste or corrupt reuse."""
        jobs = workflow((ROOT/'.github/workflows/ci.yml').read_text())['jobs']
        for job in jobs.values():
            for step in job['steps']:
                if not step.get('uses', '').startswith('actions/cache@'):
                    continue
                key = step['with']['key']
                self.assertIn('${{ runner.os }}', key)
                self.assertIn('${{ runner.arch }}', key)
                inputs = set(re.findall(r"'([^']+)'", key))
                paths = step['with']['path']
                if 'toolchain' in paths:
                    self.assertIn('spec/toolchain.json', inputs)
                elif 'model-tools' in paths:
                    self.assertIn('spec/model-tools.json', inputs)
                elif '~/.cargo/' in paths:
                    self.assertTrue({'native/**/Cargo.lock', 'spec/bandersnatch-pins.json',
                                     'spec/polkavm-pins.json', '.gitmodules'} <= inputs)
                if 'native-environment.json' in paths or '/bin/tlanif' in paths:
                    self.assertIn('${{ steps.built_cache_host.outputs.key }}', key)
                    self.assertIn('tools/managed_tools.py', inputs)
                if 'build-tools/quic/' in paths:
                    self.assertTrue({'native/quic/**', 'spec/quic-proof-pins.json',
                                     'tools/build_quic.py'} <= inputs)
                if 'build-tools/bandersnatch/' in paths:
                    self.assertTrue({'native/bandersnatch/**', 'native/crypto/**',
                                     'tools/build_bandersnatch.py', 'tools/build_crypto.py'} <= inputs)
                if 'build-tools/polkavm/' in paths:
                    self.assertTrue({'native/polkavm/**', 'tools/build_polkavm.py'} <= inputs)


if __name__ == '__main__':
    unittest.main()
