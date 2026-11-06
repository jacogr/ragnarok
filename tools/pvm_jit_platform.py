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


RESIDENT_PROOF = 'pvmX86ResidentProof'
RESIDENT_PROOF_REF = 'refs/heads/codex/pvm-x86-checked-read-resident-proof'
RESIDENT_PAIR_REF = 'refs/heads/codex/pvm-x86-checked-read-resident-pair'


def comparison_defines(system, machine, scope, ci):
    """Select the disposable resident profile only in its exact DOOM dispatch job."""
    defines = native_defines(system, machine)
    if (defines == ['pvmX86Jit'] and scope == 'doom'
            and ci.get('GITHUB_JOB') == 'pvm-comparison'
            and ci.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and ci.get('GITHUB_REF') in (RESIDENT_PROOF_REF, RESIDENT_PAIR_REF)):
        return [*defines, RESIDENT_PROOF]
    return defines
