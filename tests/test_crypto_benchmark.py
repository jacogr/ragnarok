# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect crypto correctness evidence, equal workloads, complete sampling and failed-run summaries."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import crypto_benchmark as runner
from crypto_benchmark_report import (CASES, ENGINES, SAMPLES, VECTOR_COUNT, aggregate, oracle,
                                     parse_output, summarize_benchmark)
from summarize_tests import summarize


# Author a complete sample grid from the independent oracle, without invoking native tools in Python CI.
def report():
    samples = []
    for mode, size in CASES:
        cycle, hashes = oracle(mode, size)
        iterations = 32
        checksum = sum(cycle[:iterations])
        digest = hashes[31].hex() if mode == 'hash' else hashes[0].hex()
        for engine in ENGINES:
            for pass_index in range(2):
                for sample in range(SAMPLES):
                    samples.append(dict(mode=mode, size=size, engine=engine, pass_index=pass_index,
                        sample=sample, iterations=iterations, elapsed_ns=(1000 + sample) * iterations,
                        checksum=checksum, digest=digest))
    checks = [dict(name=name, exit_code=0) for name in
              ('simd-build', 'driver-build', 'verify-baseline', 'verify-simd')]
    return dict(status='checks-passed', checks=checks, samples=samples,
                verified_vectors={engine: VECTOR_COUNT for engine in ENGINES}, cases=aggregate(samples))


class CryptoBenchmarkTests(unittest.TestCase):
    """Wrong digests, missing measurements and setup failures cannot publish a successful speed table."""

    def test_independent_fixture_and_native_corpus(self):
        """Validate fixture framing and the native corpus formula independently of timing helpers."""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'vectors.bin'
            self.assertEqual(runner.write_vectors(path), VECTOR_COUNT)
            data = path.read_bytes()
            self.assertEqual(data[:4], b'B2B1')
            self.assertEqual(struct.unpack('<I', data[4:8])[0], VECTOR_COUNT)
            self.assertEqual(data[8:12], bytes(4))
            self.assertEqual(data[12:44], hashlib.blake2b(b'', digest_size=32).digest())
        for size in (0, 33, 64, 128, 129):
            # Directly construct global input offsets, rather than reusing the oracle's repeating pattern.
            stride = max(size, 1)
            source = bytes((i * 131 + i // stride * 17 + size * 3) & 255 for i in range(stride * 3))
            _, hashes = oracle('hash', size)
            for index in range(3):
                self.assertEqual(hashes[index], hashlib.blake2b(source[index * stride:index * stride + size], digest_size=32).digest())

    def test_parser_rejects_wrong_work_and_partial_output(self):
        """A process exit and plausible elapsed time cannot substitute for the expected final result."""
        cycle, hashes = oracle('hash', 64)
        valid = f'1000 {cycle[0]} {hashes[0].hex()}\n'
        self.assertEqual(parse_output(valid, 'hash', 64, 1)['elapsed_ns'], 1000)
        for text in (valid + valid, valid.rstrip(), '0 ' + valid.split(' ', 1)[1],
                     f'1000 {cycle[0] + 1} {hashes[0].hex()}\n', f'1000 {cycle[0]} {"00" * 32}\n'):
            with self.subTest(output=text), self.assertRaises(ValueError):
                parse_output(text, 'hash', 64, 1)
        with self.assertRaises(ValueError):
            parse_output(valid, 'hash', 64, True)

    def test_complete_summary_and_rejected_mutations(self):
        """Incomplete/duplicate samples, failed vectors and forged statistics remain hard failures."""
        original = report()
        self.assertIn('64-byte hash', summarize(original, 'crypto-benchmark'))
        self.assertIn('4096-leaf Merkle', summarize_benchmark(original))
        mutations = [lambda d: d['samples'].pop(),
                     lambda d: d['samples'].append(dict(d['samples'][0])),
                     lambda d: d['samples'][0].update(elapsed_ns=0),
                     lambda d: d['samples'][0].update(checksum=-1),
                     lambda d: d['samples'][0].update(digest='00' * 32),
                     lambda d: d['samples'][0].update(sample=10),
                     lambda d: d['samples'][0].update(pass_index=True),
                     lambda d: d['samples'][0].update(size=False),
                     lambda d: d['samples'][0].update(engine='unknown'),
                     lambda d: d['verified_vectors'].pop('simd'),
                     lambda d: d['checks'][0].update(exit_code=1),
                     lambda d: d['checks'].pop(),
                     lambda d: d['cases'][0]['engines']['baseline'].update(median_ns=1)]
        for mutate in mutations:
            with self.subTest(mutation=mutate), self.assertRaises(ValueError):
                changed = deepcopy(original)
                mutate(changed)
                summarize_benchmark(changed)
        changed = deepcopy(original)
        for row in changed['samples']:
            # Even independently correct samples cannot compare engines that executed different work.
            if row['mode'] == 'hash' and row['size'] == 64 and row['engine'] == 'simd':
                cycle, hashes = oracle('hash', 64)
                row.update(iterations=1, checksum=cycle[0], digest=hashes[0].hex())
        with self.assertRaisesRegex(ValueError, 'unequal work'):
            aggregate(changed['samples'])

    def test_missing_pin_clears_old_success(self):
        """Missing setup metadata must replace a previous pass before any compiler can run."""
        original_read = Path.read_text
        def read(path, *args, **kwargs):
            # Refuse only the runtime pin read; other fixture/report reads retain normal behavior.
            if path == runner.ROOT / 'spec/bandersnatch-pins.json':
                raise FileNotFoundError('missing Rust pin')
            return original_read(path, *args, **kwargs)
        with tempfile.TemporaryDirectory() as temporary, patch.dict(runner.os.environ):
            folder = Path(temporary)
            (folder / 'results.json').write_text('old success')
            with patch.object(runner, 'BUILD', folder), patch.object(Path, 'read_text', autospec=True, side_effect=read):
                with self.assertRaisesRegex(FileNotFoundError, 'missing Rust pin'):
                    runner.run()
            self.assertEqual(json.loads((folder / 'results.json').read_text())['status'], 'failed')
            self.assertIn('missing Rust pin', (folder / 'summary.md').read_text())

    def test_failed_run_clears_old_success(self):
        """A setup failure replaces all earlier successful report/summary evidence without running compilers."""
        with tempfile.TemporaryDirectory() as temporary, patch.dict(runner.os.environ):
            folder = Path(temporary)
            for name in ('results.json', 'summary.md', 'samples.csv'):
                (folder / name).write_text('old success')
            with patch.object(runner, 'BUILD', folder), patch.object(runner.platform, 'system', return_value='unsupported'):
                with self.assertRaises(ValueError):
                    runner.run()
            self.assertEqual(json.loads((folder / 'results.json').read_text())['status'], 'failed')
            text = (folder / 'summary.md').read_text()
            self.assertIn('No complete validated comparison', text)
            self.assertNotIn('old success', text)
            self.assertFalse((folder / 'samples.csv').exists())


# Direct execution checks report contracts without building native providers.
if __name__ == '__main__':
    unittest.main()
