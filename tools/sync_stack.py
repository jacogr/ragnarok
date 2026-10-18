#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Record a tree-identical squash merge before updating a dependent PR from master.

sync_stack verifies ancestry, exact trees and a clean checkout before creating an ancestry-only
merge. The CLI accepts the original parent tip and its landed squash; it never pushes or rewrites.
"""
import argparse
from pathlib import Path
import subprocess
import sys


# Run Git in the selected checkout, returning captured output without invoking a shell.
def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


# Resolve user refs to immutable commit IDs before checks or mutations; reject non-commits.
def commit(root, ref):
    return git(root, 'rev-parse', '--verify', '--end-of-options', ref+'^{commit}')


# Only exit status one means unrelated history; other Git errors must remain fatal.
def ancestor(root, older, newer):
    result = subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', older, newer])
    if result.returncode not in (0, 1):
        # Repository failures must never authorize an ancestry-only merge.
        result.check_returncode()
    return result.returncode == 0


# Prove the landed tree is already represented by an ancestor of HEAD, then record its ancestry.
def sync_stack(root, parent, landed, upstream='origin/master'):
    upstream_name = upstream
    parent, landed, upstream = (commit(root, ref) for ref in (parent, landed, upstream))
    if (Path(root)/git(root, 'rev-parse', '--git-path', 'MERGE_HEAD')).exists():
        # Never replace an unfinished merge, including one whose tree happens to be unchanged.
        raise ValueError('Finish or abort the existing merge first')
    if git(root, 'status', '--porcelain'):
        # Refuse staged, unstaged and untracked work rather than absorbing it into a merge.
        raise ValueError('Stack synchronization requires a clean checkout')
    if not ancestor(root, parent, 'HEAD'):
        # The current branch must actually contain the original parent implementation.
        raise ValueError('Original parent is not an ancestor of HEAD')
    if not ancestor(root, landed, upstream):
        # Only reconcile a commit already landed on the specified integration branch.
        raise ValueError('Landed commit is not an ancestor of '+upstream_name)
    if git(root, 'rev-parse', parent+'^{tree}') != git(root, 'rev-parse', landed+'^{tree}'):
        # Even one differing byte requires an ordinary reviewed merge, never an ours strategy.
        raise ValueError('Parent and landed trees differ; resolve an ordinary merge instead')
    if ancestor(root, landed, 'HEAD'):
        # Repeated invocations are harmless and must not create redundant merge commits.
        return False
    subprocess.run(['git', '-C', str(root), 'merge', '--no-ff', '--strategy=ours', landed,
                    '-m', 'chore(stack): reconcile tree-identical parent squash'], check=True)
    return True


# Keep ref selection explicit; fetching, normal master merging and pushing remain reviewable steps.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parent', required=True, help='Original parent PR tip already in HEAD')
    parser.add_argument('--landed', required=True, help='Tree-identical squash commit on master')
    args = parser.parse_args()
    try:
        # Validation finishes before Git can write a merge commit.
        changed = sync_stack(Path.cwd(), args.parent, args.landed)
    except (ValueError, subprocess.CalledProcessError) as error:
        # Preserve a failing exit status so scripted callers cannot proceed after a refused merge.
        print(str(error), file=sys.stderr)
        return 1
    print('Recorded parent squash ancestry' if changed else 'Parent squash already recorded')
    return 0


# Importing the helper for tests must not mutate the caller's repository.
if __name__ == '__main__':
    sys.exit(main())
