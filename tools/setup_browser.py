#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prepare pinned Playwright tooling and a browser for the owning E2E UI check.

Exposes prepare and main. Dependencies, profiles and downloaded browsers stay under build/;
application compilation and shipped UI assets require neither Node nor Playwright.
"""
import os
from pathlib import Path
import platform
import shutil
import subprocess
from toolchain_archives import ROOT

DESTINATION = ROOT/'build/browser'


def browser_environment():
    """Select the build-owned browser cache without repurposing user/global runtime directories."""
    return {**os.environ, 'PLAYWRIGHT_BROWSERS_PATH': str(DESTINATION/'browsers')}


def system_browser():
    """Prefer an explicitly selected browser or an installed Chrome; otherwise provision Chromium."""
    requested = os.environ.get('CHROME_BIN')
    if requested:
        if not Path(requested).is_file():
            raise ValueError('CHROME_BIN does not name a browser executable')
        return requested
    if platform.system() == 'Darwin':
        chrome = Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        if chrome.is_file():
            return str(chrome)
    return shutil.which('google-chrome') or shutil.which('chromium') or ''


def prepare():
    """Install exact locked test dependencies, then ensure a headless browser is available."""
    DESTINATION.mkdir(parents=True, exist_ok=True)
    changed = False
    for name in ['package.json', 'package-lock.json']:
        data = (ROOT/'tools/browser'/name).read_bytes()
        target = DESTINATION/name
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
            changed = True
    if changed or not (DESTINATION/'node_modules/playwright/package.json').exists():
        subprocess.run(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund'],
                       cwd=DESTINATION, check=True)
    selected = system_browser()
    if not selected:
        command = ['node', str(DESTINATION/'node_modules/playwright/cli.js'), 'install',
                   '--only-shell', 'chromium']
        if platform.system() == 'Linux':
            command.insert(-1, '--with-deps') # Clean Linux hosts receive browser OS libraries too.
        subprocess.run(command, env=browser_environment(), check=True)
    (DESTINATION/'chrome-path.txt').write_text(selected)
    print('Browser UI test tools ready')


if __name__ == '__main__':
    prepare()
