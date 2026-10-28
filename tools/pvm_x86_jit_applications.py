#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""CI-only first x86 public/interpreter/PolkaVM application cohort, using the established checked protocol."""
import os
import subprocess
from native_checks import ROOT
from pvm_arm64_jit_applications import run


def main():
    """Heavy execution stays on native CI; resolve the comparison revision before any source snapshot is built."""
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('x86 application comparisons are CI-only')
    baseline = os.environ.get('PVM_COMPARE_PREPARED_BASE') or subprocess.check_output(
        ['git','rev-parse','origin/master'], cwd=ROOT, text=True).strip()
    run(architecture='x86_64', build=ROOT/'build/tests/pvm-x86-applications', baseline=baseline)


if __name__ == '__main__':
    main()
