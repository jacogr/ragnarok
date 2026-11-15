# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Require GitHub-compatible duplicate-key refusal without rejecting valid YAML merge overrides."""
from pathlib import Path
import unittest
from workflow_fixtures import workflow

ROOT = Path(__file__).resolve().parents[1]


class WorkflowConfigurationTests(unittest.TestCase):
    """Configuration accepted locally must not conceal duplicate keys that GitHub rejects."""

    def test_duplicate_explicit_defaults_refuse(self):
        """An appended input must not silently consume its predecessor's default value."""
        text = 'input:\n  type: boolean\n  default: false\n  default: jit\n'
        with self.assertRaisesRegex(ValueError, 'Duplicate workflow key default'):
            workflow(text)

    def test_merge_overrides_and_owned_results_remain_valid(self):
        """Explicit values may override an anchored default, without sharing caller mutations."""
        text = 'base: &base\n  run: first\nstep:\n  <<: *base\n  run: second\n'
        value = workflow(text)
        self.assertEqual(value['step']['run'], 'second')
        value['step']['run'] = 'changed'
        self.assertEqual(workflow(text)['step']['run'], 'second')

    def test_committed_workflows_have_valid_input_defaults(self):
        """Parse each real workflow and check the declared dispatch types, rather than field ordering."""
        for path in sorted((ROOT/'.github/workflows').glob('*.yml')):
            with self.subTest(workflow=path.name):
                value = workflow(path.read_text())
                # An input-free manual trigger may use an explicit null mapping.
                dispatch = value.get('on', {}).get('workflow_dispatch') or {}
                for field in dispatch.get('inputs', {}).values():
                    if 'default' not in field:
                        continue
                    if field['type'] == 'boolean':
                        self.assertIs(type(field['default']), bool)
                    elif field['type'] == 'choice':
                        self.assertIn(field['default'], field['options'])
                    elif field['type'] == 'string':
                        self.assertIsInstance(field['default'], str)


if __name__ == '__main__':
    unittest.main()
