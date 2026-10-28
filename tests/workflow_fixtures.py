# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Inspect literal CI job sections and evaluate the small scheduling-expression subset under test."""
import ast
import json
import re


# Supply complete event fields so absent labels never masquerade as a heavy request.
def event_context(event='push', action='', label='', suite='', state='open', merged=False):
    return dict(github=dict(event_name=event, event=dict(action=action, label=dict(name=label),
                                                          pull_request=dict(state=state, merged=merged))),
                inputs=dict(suite=suite))


# Interpret only the operators used by the workflow; never execute arbitrary Python from YAML.
def expression(source, context):
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
            if node.func.id == 'always' and not node.args:
                return True
            if node.func.id == 'cancelled' and not node.args:
                return context.get('cancelled', False)
        raise ValueError('Unsupported workflow expression: '+ast.dump(node))

    return value(tree.body)


# Exact job boundaries keep neighboring workloads out of a family's evidence checks.
def job_section(text, job):
    return re.search(r'^  '+re.escape(job)+r':\n(.*?)(?=^  [\w-]+:|\Z)',
                     text, re.MULTILINE | re.DOTALL).group(1)


# Resolve the one shared job condition without importing a YAML dependency into tooling tests.
def job_condition(text, job):
    section = job_section(text, job)
    guard = re.search(r'^    if: (.+)$', section, re.MULTILINE).group(1)
    if guard.startswith('*'):
        # A missing anchor must fail the test instead of defaulting to a permissive condition.
        anchor = re.escape(guard[1:])
        return re.search(r'^    if: &'+anchor+r' (.+)$', text, re.MULTILINE).group(1)
    return re.sub(r'^&[\w-]+ ', '', guard)


# Evaluate the actual job guard and matrix expression for each PR/manual/master scenario.
def selected_families(text, job, context):
    section = job_section(text, job)
    guard = job_condition(text, job)
    if not expression(guard, context):
        return []
    matrix = re.search(r'^        family: (.+)$', section, re.MULTILINE)
    if matrix is not None:
        # Dynamic matrices select scoped workloads from event inputs.
        return expression(matrix.group(1), context)
    # Native host records use YAML aliases so runner upgrades have one definition per architecture.
    records = re.search(r'^        family:\n((?:          .+\n|            .+\n)+)', section, re.MULTILINE)
    if records is not None and '          - name:' in records.group(1):
        rows = []
        for record in records.group(1).split('          - ')[1:]:
            row = {}
            for key, item in re.findall(r'^\s*([\w-]+): (.+)$', record, re.MULTILINE):
                if item.startswith('*'):
                    item = re.search(r'&'+re.escape(item[1:])+r' ([\w.-]+)', text).group(1)
                row[key] = re.sub(r'^&[\w-]+ ', '', item)
            rows.append(row)
        return rows
    # Static E2E families retain their readable source-owned YAML declarations.
    return [dict(group=group, name=name) for group, name in re.findall(
        r'^          - \{group: ([a-z_]+), name: ([^}\n]+)\}$', section, re.MULTILINE)]


# Retain only steps applicable to one family; native commands never execute during these checks.
def family_section(text, job, group, name=None, context=None):
    section = job_section(text, job)
    request = event_context() if context is None else context
    family = next(row for row in selected_families(text, job, request)
                  if row['group'] == group and (name is None or row['name'] == name))
    context = dict(request, matrix=dict(family=family, os=re.search(r'&ubuntu-x86-version ([\w.-]+)', text).group(1)))
    header, steps = section.split('    steps:\n', 1)
    kept = []
    for step in re.findall(r'^      - .*?(?=^      - |\Z)', steps, re.MULTILINE | re.DOTALL):
        guard = re.search(r'^        if: (.+)$', step, re.MULTILINE)
        if guard is None or expression(guard.group(1), context):
            kept.append(step)
    return header+'    steps:\n'+''.join(kept)
