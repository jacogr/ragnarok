# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check shared native compiler profiles and isolated workspaces.

Exposes VerificationProfiles for unittest discovery; test methods exercise the stated contracts.
"""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from native_checks import NativeChecks


# Keep profiles ownership and failure safeguards independent of other verification groups.
class VerificationProfiles(unittest.TestCase):
    # Unit and E2E compilation must retain identical checked platform profiles in independent workspaces.
    def test_shared_native_compiler_profiles(self):
        for system in ('Linux', 'Darwin'):
            # Command planning exercises both hosts without executing an unrelated compiler or native ABI.
            with self.subTest(system=system), patch('native_checks.platform.system', return_value=system):
                caches = set()
                for group in ('unit', 'failures', 'e2e'):
                    # Equal source names in different groups must never share executable or compiler outputs.
                    checks = NativeChecks(ROOT/'build/fixture-groups'/group)
                    with patch.object(checks, 'command', return_value=dict(exit_code=0)) as command:
                        _, binary = checks.build(Path('/fixture/nimony'), ROOT/'src/quic/peer.nim', 'peer',
                                                  quic_library=Path('/fixture/libquic'), defines=('integration',))
                    arguments = command.call_args.args[0]
                    self.assertEqual(binary.parent, checks.folder)
                    for flag in ('--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
                                 '--boundchecks:on', '--passC:-flto', '--passL:-flto', '-d:integration'):
                        # Every executable retains guards, ARC, native optimization and the explicit feature profile.
                        self.assertIn(flag, arguments)
                    self.assertEqual('--passL:-fuse-ld=lld' in arguments, system == 'Linux')
                    caches.add(next(arg for arg in arguments if str(arg).startswith('--nimcache:')))
                self.assertEqual(len(caches), 3)


# Direct execution uses the same safeguards as normal unittest discovery.
if __name__ == '__main__':
    unittest.main()
