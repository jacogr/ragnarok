# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Select only maintained native JIT build targets; unsupported hosts keep checked interpretation.

The production builder and real CLI parity driver share this pure flag plan. It never invokes a
compiler, probes executable storage or changes the runtime requested-policy/actual-engine rules.
"""
import platform


def native_defines(system=None, machine=None):
    """Linux x86-64 and Linux/macOS ARM64 select their own emitter; every other host enables neither."""
    system = platform.system() if system is None else system
    machine = (platform.machine() if machine is None else machine).lower()
    if system == 'Linux' and machine in ('x86_64', 'amd64', 'x64'):
        return ['pvmX86Jit']
    if system in ('Linux', 'Darwin') and machine in ('arm64', 'aarch64'):
        return ['pvmArm64Jit']
    return []
