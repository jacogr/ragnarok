# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify parallel codec cache ownership, complete execution, strict failure and ordered output."""
import io
from pathlib import Path
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from harness_fixtures import temporary_folder

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import native_codec


class NativeCodecWorkers(unittest.TestCase):
    """Keep each codec main independent while sharing compiler state only inside a serial worker."""

    def test_private_reuse_order_and_failure(self):
        """Workers overlap, caches do not, every test executes and failures survive sibling successes."""
        for failed in (None, 'b'):
            with self.subTest(failed=failed), temporary_folder() as folder:
                names = ('a', 'b', 'c', 'd')
                for name in names:
                    # Sources/goldens exist only for planner validation; fake commands never execute them.
                    (folder/(name+'.nim')).touch()
                    (folder/(name+'.output')).touch()
                arguments = ['hastur', '--cachedir:'+str(folder/'cache'), '--jobs:2',
                             '--joined:off', '--forward:--mm:arc', 'test', str(folder)]
                barrier, calls = threading.Barrier(2), []
                def run(command, **options):
                    """Require real overlap and record the worker's complete compiler profile."""
                    name = Path(command[-1]).stem
                    calls.append((name, command))
                    if name in ('a', 'c'):
                        barrier.wait(timeout=5)
                    return SimpleNamespace(returncode=1 if name == failed else 0,
                                           stdout=name+'\n', stderr='')
                with patch.object(native_codec, 'UNIT_ROOT', folder), \
                     patch.object(native_codec, 'unit_batches', return_value=[('codec', names, None)]), \
                     patch.object(native_codec, 'unit_source', side_effect=lambda name: folder/(name+'.nim')), \
                     patch.object(native_codec.subprocess, 'run', side_effect=run), \
                     patch('sys.stdout', new_callable=io.StringIO) as output:
                    status = native_codec.run_codec_batch(arguments)
                self.assertEqual(status, 0 if failed is None else 1)
                self.assertCountEqual([name for name, _ in calls], names)
                caches = {name: next(arg for arg in command if arg.startswith('--cachedir:'))
                          for name, command in calls}
                self.assertEqual(caches['a'], caches['b'])
                self.assertEqual(caches['c'], caches['d'])
                self.assertNotEqual(caches['a'], caches['c'])
                for _, command in calls:
                    self.assertIn('--jobs:1', command)
                    self.assertIn('--joined:off', command)
                    self.assertIn('--forward:--mm:arc', command)
                text = output.getvalue()
                self.assertLess(text.index('a\n'), text.index('b\n'))
                self.assertLess(text.index('b\n'), text.index('c\n'))
                self.assertLess(text.index('c\n'), text.index('d\n'))

    def test_invalid_scope_or_missing_golden_refuses_before_execution(self):
        """No malformed command, empty scope or missing expected output can become a green batch."""
        with temporary_folder() as folder:
            arguments = ['hastur', '--cachedir:'+str(folder/'cache'), '--jobs:2',
                         '--joined:off', 'test', str(folder)]
            with patch.object(native_codec, 'UNIT_ROOT', folder), \
                 patch.object(native_codec.subprocess, 'run') as run:
                for changed in (arguments[:-1]+[str(folder/'other')],
                                [arg if arg != '--jobs:2' else '--jobs:5' for arg in arguments],
                                [arg for arg in arguments if arg != '--joined:off']):
                    with self.assertRaises(ValueError):
                        native_codec.run_codec_batch(changed)
                with patch.object(native_codec, 'unit_batches', return_value=[('codec', (), None)]):
                    with self.assertRaises(ValueError):
                        native_codec.run_codec_batch(arguments)
                (folder/'sample.nim').touch()
                with patch.object(native_codec, 'unit_batches', return_value=[('codec', ('sample',), None)]), \
                     patch.object(native_codec, 'unit_source', return_value=folder/'sample.nim'):
                    with self.assertRaises(FileNotFoundError):
                        native_codec.run_codec_batch(arguments)
                run.assert_not_called()
