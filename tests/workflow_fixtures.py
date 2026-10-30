# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Read parsed CI configuration and evaluate only the scheduling expressions under test."""
import ast
from copy import deepcopy
from functools import lru_cache
import yaml
import json
import re


# Supply complete event fields so absent labels never masquerade as a heavy request.
def event_context(event='push', action='', label='', suite='', state='open', merged=False):
    return dict(github=dict(event_name=event, event=dict(action=action, label=dict(name=label),
                                                          pull_request=dict(state=state, merged=merged))),
                inputs=dict(suite=suite))


# Interpret only the operators used by the workflow; never execute arbitrary Python from YAML.
def expression(source, context):
    if isinstance(source, bool):
        # YAML accepts literal booleans as well as GitHub expression strings.
        return source
    source = source.removeprefix('${{').removesuffix('}}').strip()
    source = re.sub(r'!(?!=)', 'not ', source).replace('&&', ' and ').replace('||', ' or ')
    tree = ast.parse(source.strip(), mode='eval')

    # Explicit AST cases preserve short-circuit value selection used by fromJSON matrices.
    def value(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Name):
            return context[node.id]
        if isinstance(node, ast.Attribute):
            return value(node.value).get(node.attr, '')
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            return not value(node.operand)
        if isinstance(node, ast.BoolOp):
            for operand in node.values:
                result = value(operand)
                # GitHub's &&/|| expressions return the selected operand, not a coerced boolean.
                if (isinstance(node.op, ast.And) and not result) or (isinstance(node.op, ast.Or) and result):
                    return result
            return result
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            left, right = value(node.left), value(node.comparators[0])
            if isinstance(node.ops[0], ast.Eq):
                return left == right
            if isinstance(node.ops[0], ast.NotEq):
                return left != right
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            if node.func.id == 'fromJSON' and len(node.args) == 1:
                return json.loads(value(node.args[0]))
            if node.func.id == 'format' and node.args:
                return value(node.args[0]).format(*(value(arg) for arg in node.args[1:]))
            if node.func.id == 'always' and not node.args:
                return True
            if node.func.id == 'cancelled' and not node.args:
                return context.get('cancelled', False)
        raise ValueError('Unsupported workflow expression: '+ast.dump(node))

    return value(tree.body)


# Parse YAML once per input; return owned data so mutation witnesses cannot contaminate later tests.
@lru_cache(maxsize=8)
def _parsed_workflow(text):
    """Use safe constructors, including anchors, without a layout-specific workflow parser."""
    return yaml.load(text, Loader=getattr(yaml, 'CSafeLoader', yaml.SafeLoader))


def workflow(text):
    """Return a caller-owned parsed document for configuration and mutation checks."""
    return deepcopy(_parsed_workflow(text))


# Job identifiers locate the relevant consumer; labels, indentation and declaration order do not.
def job_section(text, job):
    return workflow(text)['jobs'][job]


def job_condition(text, job):
    """An omitted guard means the job is enabled by default."""
    return job_section(text, job).get('if', True)


# Evaluate only the configured family selector, without reproducing a GitHub Actions scheduler.
def selected_families(text, job, context):
    section = job_section(text, job)
    if not expression(section.get('if', True), context):
        return []
    families = section.get('strategy', {}).get('matrix', {}).get('family', [])
    return expression(families, context) if isinstance(families, str) else families


def selected_steps(section, family, context):
    """Select a family's applicable commands without executing native or network work."""
    request = dict(context, matrix=dict(family=family))
    return [step for step in section['steps'] if expression(step.get('if', True), request)]


def family_section(text, job, group, name=None, context=None):
    """Return parsed job data with only the requested family's steps."""
    section = job_section(text, job)
    request = event_context() if context is None else context
    family = next(row for row in selected_families(text, job, request)
                  if row['group'] == group and (name is None or row['name'] == name))
    section['steps'] = selected_steps(section, family, request)
    return section


def commands(section):
    """Expose executable shell content, excluding display labels and comments in YAML."""
    return [step['run'] for step in section['steps'] if 'run' in step]


def artifact_paths(section):
    """Expose artifact consumer paths independently of scalar/block YAML spelling."""
    return [path.strip() for step in section['steps'] if 'actions/upload-artifact@' in step.get('uses', '')
            for path in step.get('with', {}).get('path', '').splitlines() if path.strip()]
