# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise namespace enforcement across source areas and flat native test directories."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from module_naming import module_imports, validate_module_names


class ModuleNaming(unittest.TestCase):
    # Build a tiny source tree without invoking setup, compilers or dependency providers.
    def tree(self, folder):
        root = Path(folder)
        for name in ('src/pvm/backend.nim', 'src/state/backend.nim',
                     'src/future/internal/backend.nim', 'src/version.nim'):
            path = root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('discard\n')
        (root/'tests/unit').mkdir(parents=True)
        return root

    # Both existing and newly introduced areas must use their owning namespace, including internals.
    def test_owned_aliases(self):
        with tempfile.TemporaryDirectory() as folder:
            root = self.tree(folder)
            consumer = root/'tests/unit/test_pvm_backend.nim'
            consumer.write_text('import ../../src/pvm/backend as pvm_backend\n'
                                'import ../../src/state/backend as state_backend\n'
                                'import ../../src/future/internal/backend as future_backend\n'
                                'import ../../src/version as ragnarok_version\n')
            self.assertEqual(validate_module_names(root), (4, 1))
            for declaration in ('import ../../src/pvm/backend',
                                'import ../../src/pvm/backend as state_backend',
                                'import ../../src/future/internal/backend as backend',
                                'from ../../src/pvm/backend import PvmBackend'):
                consumer.write_text(declaration+'\n')
                with self.subTest(declaration=declaration), self.assertRaisesRegex(ValueError, ' as '):
                    validate_module_names(root)

    # Comments, fixture strings and includes cannot manufacture alias violations.
    def test_import_forms(self):
        text = '''#[ import src/pvm/backend ]#
let fixture = """import src/state/backend"""
import std/[os, tables]
import ./[backend as pvm_backend,
          machine as pvm_machine]
import "../src/version" as ragnarok_version
from ./backend import PvmBackend
include ./generated
'''
        self.assertEqual(list(module_imports(text)), [
            ('std/os', None), ('std/tables', None), ('./backend', 'pvm_backend'),
            ('./machine', 'pvm_machine'), ('../src/version', 'ragnarok_version'),
            ('./backend', None)])

    # Only source-owned module bindings need aliases; selective imports also use an alias; textual includes stay valid.
    def test_nonbinding_imports(self):
        with tempfile.TemporaryDirectory() as folder:
            root = self.tree(folder)
            (root/'src/pvm/consumer.nim').write_text(
                'from ./backend as pvm_backend import PvmBackend\ninclude ./backend\nimport std/os\n')
            self.assertEqual(validate_module_names(root), (5, 0))

    # Flat test basenames need an area even though their production files retain directory namespaces.
    def test_flat_names(self):
        with tempfile.TemporaryDirectory() as folder:
            root = self.tree(folder)
            source = root/'tests/unit/test_backend.nim'
            source.write_text('discard\n')
            with self.assertRaisesRegex(ValueError, 'Native test must use'):
                validate_module_names(root)
            source.rename(source.with_name('test_future_backend.nim'))
            self.assertEqual(validate_module_names(root), (4, 1))


if __name__ == '__main__':
    unittest.main()
