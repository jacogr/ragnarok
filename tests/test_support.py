# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Shared repository identity for independent references; application assertions live in Nim.

Exposes ROOT, the repository path used by independent test references and fixture loaders.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
