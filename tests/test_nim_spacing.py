# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Exercise source-spacing fixes, literal preservation and the shared formatter's check mode."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from nim_spacing import normalize_spacing

SPEC = importlib.util.spec_from_file_location('source_format',
                                            Path(__file__).resolve().parents[1]/'tools/format.py')
FORMAT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FORMAT)


class NimSpacingTests(unittest.TestCase):
    """Spacing changes must be repeatable and must preserve program and fixture contents."""

    def test_header_and_module_documentation(self):
        """Separate the license, complete module documentation and first import."""
        source = ('# Copyright (c) 2026 Ragnarök contributors\n'
                  '# SPDX-License-Identifier: MIT OR Apache-2.0\n'
                  '## Module purpose.\n## Its ownership contract.\nimport std/assertions\n')
        expected = source.replace('Apache-2.0\n', 'Apache-2.0\n\n').replace(
            'contract.\n', 'contract.\n\n')
        self.assertEqual(normalize_spacing(source), expected)
        self.assertEqual(normalize_spacing(expected), expected)

    def test_routine_sections_and_attached_comments(self):
        """One separator precedes a routine and its explanatory comments, including forward declarations."""
        source = ('proc first() =\n  discard\n\n\nproc second() = discard\n'
                  '# Explain the next routine.\nproc third()\nproc fourth()\n')
        expected = ('proc first() =\n  discard\n\nproc second() = discard\n\n'
                    '# Explain the next routine.\nproc third()\n\nproc fourth()\n')
        self.assertEqual(normalize_spacing(source), expected)
        self.assertEqual(normalize_spacing(expected), expected)

    def test_nested_declarations(self):
        """Nested declarations retain their grouping while excessive blank lines collapse."""
        source = 'when defined(example):\n  proc first()\n  proc second()\n\n\n  discard\n'
        self.assertEqual(normalize_spacing(source), source.replace('\n\n\n', '\n\n'))

    def test_multiline_values_and_nested_comments(self):
        """Code-looking text and blank runs inside multiline tokens are byte-for-byte unchanged."""
        values = [
            'let text = """\n\n\nproc fake()\n## Fake module.\n\n\n"""\n',
            '#[\n\n\n#[ Nested. ]#\nproc fake()\n\n\n]#\n',
            '##[\n\n\n##[ Nested documentation. ]##\nproc fake()\n\n\n]##\n',
        ]
        for source in values:
            with self.subTest(source=source):
                self.assertEqual(normalize_spacing(source), source)

    def test_quotes_and_comment_markers(self):
        """Quoted markers, escaped quotes, raw strings, chars and numeric suffixes do not leak state."""
        source = ('let a = "\\\"#["\nlet b = r"""quoted"""\n'
                  'let c = r"a""#[b"\nlet d = \'"\'\nlet n = 0\'u32\n'
                  '# """ in a line comment\n\n\nproc real() = discard\n')
        self.assertEqual(normalize_spacing(source), source.replace('\n\n\n', '\n\n'))

    def test_multiline_quote_run_endings(self):
        """Four or more closing quotes must not expose the next literal to whitespace rewriting."""
        for count in range(4, 13):
            with self.subTest(quotes=count):
                source = ('let first = """x' + '"' * count + '\n'
                          'let second = """\n\n\npayload\nproc fake()\n"""\n')
                self.assertEqual(normalize_spacing(source), source)
                # The scanner must also leave the literal and resume normal section formatting.
                self.assertEqual(normalize_spacing(source + '\n\n\nproc real()\n'),
                                 source + '\nproc real()\n')

    def test_pinned_formatter_output_is_normalized(self):
        """The production formatter applies the spacing pass after nimpretty."""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'example.nim'
            path.write_text('proc a()\n\n\nproc b()\n')
            with patch.object(FORMAT.subprocess, 'run', return_value=subprocess.CompletedProcess(
                    [], 0, stdout=path.read_bytes())):
                self.assertEqual(FORMAT.format_source(path), b'proc a()\n\nproc b()\n')

    def test_check_write_and_recheck(self):
        """Check mode fails without writing; write mode fixes every owned source root and recheck passes."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            paths = []
            for directory in ('src', 'tests', 'spec', 'native', 'tools'):
                path = root/directory/'example.nim'
                path.parent.mkdir()
                path.write_text('proc a()\n\n\nproc b()\n')
                paths.append(path)
            with patch.object(FORMAT, 'ROOT', root), \
                    patch.object(FORMAT, 'format_rust', return_value=True), \
                    patch.object(FORMAT, 'format_source',
                                 side_effect=lambda path: normalize_spacing(path.read_text()).encode()), \
                    contextlib.redirect_stdout(io.StringIO()):
                with patch('sys.argv', ['format.py', '--check']), self.assertRaises(SystemExit) as error:
                    FORMAT.main()
                self.assertEqual(error.exception.code, 1)
                self.assertTrue(all('\n\n\n' in path.read_text() for path in paths))
                with patch('sys.argv', ['format.py']):
                    FORMAT.main()
                self.assertTrue(all(path.read_text() == 'proc a()\n\nproc b()\n' for path in paths))
                with patch('sys.argv', ['format.py', '--check']):
                    FORMAT.main()
