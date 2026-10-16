"""CI safeguards for trusted archives, complete source inventories and honest partial-coverage reporting."""
import io
import json
from pathlib import Path
import sys
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from setup_ci_linux import download, extract
from setup_nimony_ci_linux import verify_identity, verify_version
from summarize_nimony_ci import summarize
import audit_nimony_modules as modules


# Build tiny inert tar fixtures; no test executes a downloaded or fabricated compiler.
def archive(name, data=b'fixture'):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w') as tar:
        member = tarfile.TarInfo(name)
        member.size = len(data)
        tar.addfile(member, io.BytesIO(data))
    return output.getvalue()


# Rejection paths prevent archive substitution, source omissions and misleading green migration summaries.
class NimonyCISafeguards(unittest.TestCase):
    # A stale/corrupt retained download must fail without trusting its filename or using the network.
    def test_cached_checksum_mismatch(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'tool.archive'
            path.write_bytes(b'changed bytes')
            with patch('urllib.request.urlopen', side_effect=AssertionError('unexpected network')):
                with self.assertRaises(ValueError):
                    download(dict(url='https://example.invalid/release', sha256='0'*64), path)

    # Data filtering must reject traversal rather than create a file outside the installation directory.
    def test_archive_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(tarfile.FilterError):
                extract(archive('tool/../../escaped'), root/'install')
            self.assertFalse((root/'escaped').exists())

    # Multiple archive roots must fail before any files are extracted into runner storage.
    def test_archive_multiple_roots(self):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w') as tar:
            # Independent roots are an unexpected asset layout, not a usable binary path.
            for name in ('first/tool', 'second/tool'):
                member = tarfile.TarInfo(name)
                tar.addfile(member)
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                extract(data.getvalue(), Path(temporary))
            self.assertEqual(list(Path(temporary).iterdir()), [])

    # Same-version archives for a different platform or commit are not accepted as the selected nightly.
    def test_identity_mismatch(self):
        pins = json.loads((ROOT/'spec/nimony-ci-toolchain.json').read_text())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'NIGHTLY.txt').write_text('nimony-commit: '+pins['commit']+'\ndate: '+pins['date']+'\nplatform: macos_arm64\n')
            with self.assertRaisesRegex(ValueError, 'platform'):
                verify_identity(root, pins)

    # Real child processes reproduce stdout/stderr behavior without downloading or executing a fixture compiler.
    def test_version_streams_and_rejections(self):
        real_output = subprocess.check_output
        # Both supported stream placements must pass; a wrong/empty banner or failing command must remain rejected.
        for stream, banner, code, failure in (
                ('stderr', '0.6.3 [linux; amd64]\n', 0, None),
                ('stdout', '0.6.3 [linux; amd64]\n', 0, None),
                ('stderr', '0.6.30 [linux; amd64]\n', 0, ValueError),
                ('stderr', '', 0, ValueError),
                ('stderr', '0.6.3 [linux; amd64]\n', 1, subprocess.CalledProcessError)):
            with self.subTest(stream=stream, banner=banner, code=code):
                # Translate only the executable under test; preserve the helper's actual subprocess capture/check options.
                def output(command, **options):
                    self.assertEqual(command, ['/fixture/nimony', '--version'])
                    script = 'import sys; sys.'+stream+'.write('+repr(banner)+'); sys.exit('+str(code)+')'
                    return real_output([sys.executable, '-c', script], **options)
                with patch('setup_nimony_ci_linux.subprocess.check_output', side_effect=output):
                    if failure is None:
                        # The exact banner is retained for CI diagnostics as well as pin validation.
                        self.assertEqual(verify_version(Path('/fixture/nimony'), '0.6.3'), banner)
                    else:
                        # Mismatches and process failures cannot authorize a successful compiler setup.
                        with self.assertRaises(failure):
                            verify_version(Path('/fixture/nimony'), '0.6.3')

    # Inventory discovery must include a newly added module and keep a failed module red while checking later files.
    def test_inventory_failure_and_new_module(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'src').mkdir()
            # The third file represents new code that must not rely on a manually updated allowlist.
            for name in ('a.nim', 'b.nim', 'new.nim'):
                (root/'src'/name).write_text('discard\n')
            def check(compiler, source, folder):
                return dict(source=str(source.relative_to(root)), passed=source.name != 'b.nim')
            with patch.object(modules, 'ROOT', root), patch.object(modules, 'check_module', side_effect=check), patch.object(modules.subprocess, 'check_output', return_value='fixture'), patch('sys.stdout', new=io.StringIO()):
                report = modules.audit(root/'nimony', root/'evidence')
            self.assertEqual(report['status'], 'migration-incomplete')
            self.assertEqual(len(report['modules']), 3)
            self.assertEqual([row['source'] for row in report['modules']], ['src/a.nim', 'src/b.nim', 'src/new.nim'])
            self.assertTrue((root/'evidence/results.json').is_file())

    # A stalled compiler cannot be counted as a pass or silently disappear from the inventory.
    def test_module_timeout_is_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root/'module.nim'
            source.write_text('discard\n')
            with patch.object(modules, 'ROOT', root), patch.object(modules.subprocess, 'run', side_effect=subprocess.TimeoutExpired('compiler', 180)):
                row = modules.check_module(root/'nimony', source, root)
            self.assertFalse(row['passed'])
            self.assertEqual(row['exit_code'], 124)
            self.assertIn('exceeded 180 seconds', (root/row['log']).read_text())

    # The always-run renderer still fails when the preceding runner never produced usable evidence.
    def test_missing_report_cli(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root/'summary.md'
            result = subprocess.run([sys.executable, str(ROOT/'tools/summarize_nimony_ci.py'), '--kind', 'slice',
                                     '--report', str(root/'missing.json'), '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('No usable verification report', output.read_text())

    # Compilation failure remains visible and explicitly does not claim linked/runtime conformance.
    def test_module_summary_failure(self):
        text = summarize(dict(modules=[dict(source='src/a.nim', passed=True), dict(source='src/b.nim', passed=False)]), 'modules')
        self.assertIn('1/2 modules', text)
        self.assertIn('| `src/b.nim` | Fail |', text)
        self.assertIn('does not establish linking, runtime parity', text)
        with self.assertRaises(ValueError):
            summarize(dict(modules=[]), 'modules')

    # A failed network matrix must remain visible without inflating corpus or contract-guard totals.
    def test_peer_summary_scope(self):
        report = dict(status='blocked', suites=[], runtime=[], privacy=[], nominal=[], schemas=[],
                      quic_peer=dict(passed=False, matrix_cases=16, repeated_valid=12))
        text = summarize(report, 'slice')
        self.assertIn('Authenticated CE 143 peer matrix: Fail', text)
        self.assertIn('Matrix cases: 16; repeated valid startups: 12', text)
        self.assertIn('Runtime misuse rejections: 0', text)
        self.assertIn('Independent corpora: 0', text)

    # Independent lifecycle verdicts must stay visible without counting network waves as compiler or corpus checks.
    def test_retained_summary_scope(self):
        report = dict(status='blocked', suites=[], runtime=[], privacy=[], nominal=[], schemas=[],
                      quic_service=dict(passed=True, result=dict(rounds=16, idle=[{}]*16,
                                                               accepted_and_retired_connections=66)),
                      quic_integration_service=dict(passed=False, failure='cancelled owner remained live'))
        text = summarize(report, 'slice')
        self.assertIn('Retained CE 143 service: Pass', text)
        self.assertIn('Waves: 16; retired connections: 66', text)
        self.assertIn('Integrated digest service: Fail', text)
        self.assertIn('Independent corpora: 0', text)
        self.assertIn('Runtime misuse rejections: 0', text)

    # Dynamic guard counts exclude the separate language probes and never turn a partial slice into full parity.
    def test_slice_summary_scope(self):
        report = dict(status='partial-checks-passed', suites=[dict(passed=True)], runtime=[dict(passed=True)],
                      fields=[dict(passed=True), dict(passed=True)], privacy=[dict(passed=True)], nominal=[], schemas=[], contracts=[dict(passed=True)],
                      ownership_compile=[dict(passed=True)], example_corpus=dict(passed=False, requests=3))
        text = summarize(report, 'slice')
        self.assertIn('Runtime misuse rejections: 2', text)
        self.assertIn('Compilation rejections: 3', text)
        self.assertIn('partial evidence', text)
        self.assertIn('| `example_corpus` | Fail | 3 |', text)
        with self.assertRaises(KeyError):
            summarize({}, 'slice')


# Imports expose inert test helpers without downloading tools or starting compilation.
if __name__ == '__main__':
    unittest.main(verbosity=2)
