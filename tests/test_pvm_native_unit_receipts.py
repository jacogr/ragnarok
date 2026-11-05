# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert native qualification checks preserve declared flags and require complete unit output."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_arm64_jit
import pvm_x86_jit
from native_tests import NATIVE_REQUIREMENTS, unit_source


class AfterUnit(Exception):
    """Stop only after the real unit gate reaches its subsequent ownership qualification."""


class NativeUnitReceiptTests(unittest.TestCase):
    """Exercise each real controller with its ordered plan restricted to the relevant unit."""

    def run_gate(self, architecture, output, *, native=True, refused=False, routing=False):
        """Record real flag assembly and output refusal without compiling or executing code."""
        module = pvm_arm64_jit if architecture == 'arm' else pvm_x86_jit
        name = 'pvm_stream_all_opcodes'
        plan = module.qualification_cases(native) if architecture == 'arm' else module.qualification_cases()
        case = next(row for row in plan if row[0] == 'all-opcodes')
        if architecture == 'arm':
            # Native/refusal controls retain the actual ARM profile chosen by the controller.
            defines = [*case[2], *(['pvmArm64JitRefuse'] if refused else [])]
            case = (case[0], case[1], defines)
        else:
            # Feed the controller's existing refused-mode input, without changing its flag policy.
            case = (case[0], case[1], refused)
        captured = []
        profile = dict(NATIVE_REQUIREMENTS[name])
        if routing:
            # A second allowed receipt proves the controller reads the declaration, not a copied flag.
            profile['defines'] = [*profile['defines'], 'pvmInnerPreparedReceipt']
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)

            class Checks:
                """Supply classified storage output and stop after the actual unit gate succeeds."""
                def __init__(self):
                    self.folder = folder

                def build(self, compiler, source, target, **options):
                    """Capture only the unit's compiler-bound profile; other units never run."""
                    if target != 'all-opcodes':
                        raise AfterUnit()
                    captured.append(options['defines'])
                    return dict(exit_code=0, output=''), folder/target

                def command(self, arguments, target, **options):
                    """Return exact backend storage controls and caller-selected corpus output."""
                    if target == 'memory-build':
                        return dict(exit_code=0, output='')
                    if target == 'memory-run':
                        if architecture == 'x86':
                            value = 'X86_EXECUTABLE_MEMORY_OK,1000\n'
                        else:
                            value = ('ARM_MEMORY_OK,1000,capacity,publication,retirement,integer64\n'
                                     if native else 'ARM_MEMORY_UNAVAILABLE,checked-fallback\n')
                        return dict(exit_code=0, output=value)
                    assert target == 'all-opcodes-run'
                    return dict(exit_code=0, output=output)

            with patch.object(module, 'qualification_cases', return_value=(case,)), patch.dict(
                    NATIVE_REQUIREMENTS, {name: profile}):
                try:
                    if architecture == 'arm':
                        module.qualify(Checks(), Path('/compiler'), native=native)
                    else:
                        module.qualify(Checks(), Path('/compiler'))
                except AfterUnit:
                    return captured
        self.fail('Controller did not reach the subsequent ownership gate')

    def test_declared_receipts_and_backend_flags_reach_each_compiler(self):
        """Every native/refused/fallback mode keeps its backend flags and shared receipt routing."""
        expected = unit_source('pvm_stream_all_opcodes').with_suffix('.output').read_text()
        for architecture, native, refused in [('arm', True, False), ('arm', True, True),
                                               ('arm', False, False), ('x86', True, False),
                                               ('x86', True, True)]:
            with self.subTest(architecture=architecture, native=native, refused=refused):
                captured = self.run_gate(architecture, expected, native=native, refused=refused,
                                         routing=True)
                self.assertEqual(len(captured), 1)
                backend = (['pvmArm64Jit'] if native else []) if architecture == 'arm' else ['pvmX86Jit']
                if refused:
                    backend.append('pvmArm64JitRefuse' if architecture == 'arm' else 'pvmX86JitRefuse')
                self.assertEqual(captured[0], [*backend,
                    *NATIVE_REQUIREMENTS['pvm_stream_all_opcodes']['defines'], 'pvmInnerPreparedReceipt'])

    def test_missing_activation_line_cannot_qualify_either_backend(self):
        """A zero-exit original corpus without its final activation receipt remains incomplete."""
        lines = unit_source('pvm_stream_all_opcodes').with_suffix('.output').read_text().splitlines()
        incomplete = '\n'.join(lines[:-1])+'\n'
        for architecture in ('arm', 'x86'):
            with self.subTest(architecture=architecture), self.assertRaisesRegex(
                    ValueError, 'Incomplete all-opcode qualification output'):
                self.run_gate(architecture, incomplete)

    def test_activation_tail_alone_cannot_replace_the_full_corpus(self):
        """A matching final receipt cannot hide skipped original or prefix cases."""
        lines = unit_source('pvm_stream_all_opcodes').with_suffix('.output').read_text().splitlines()
        for architecture in ('arm', 'x86'):
            with self.subTest(architecture=architecture), self.assertRaisesRegex(
                    ValueError, 'Incomplete all-opcode qualification output'):
                self.run_gate(architecture, lines[-1]+'\n')
