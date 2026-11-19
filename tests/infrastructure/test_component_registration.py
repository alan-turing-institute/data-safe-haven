"""Every Pulumi ComponentResource constructor must register completion."""

import ast
from pathlib import Path

from data_safe_haven import infrastructure


def test_every_component_registers_outputs_once_at_end_of_constructor():
    root = Path(infrastructure.__file__).resolve().parent
    inspected = []
    for source in root.rglob("*.py"):
        tree = ast.parse(source.read_text(encoding="utf-8"))
        for component in ast.walk(tree):
            if not isinstance(component, ast.ClassDef):
                continue
            if not any(
                isinstance(base, ast.Name) and base.id == "ComponentResource"
                for base in component.bases
            ):
                continue
            constructor = next(
                node
                for node in component.body
                if isinstance(node, ast.FunctionDef) and node.name == "__init__"
            )
            registrations = [
                call
                for call in ast.walk(constructor)
                if isinstance(call, ast.Call)
                and isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "self"
                and call.func.attr == "register_outputs"
            ]
            assert (
                len(registrations) == 1
            ), f"{source.name}:{component.name} must register outputs once"
            final_statement = constructor.body[-1]
            assert isinstance(final_statement, ast.Expr), component.name
            assert (
                final_statement.value is registrations[0]
            ), f"{component.name} must register after setting up child resources"
            inspected.append(component.name)
    assert len(inspected) == 31
