#!/usr/bin/env python3
"""Render each Mustache YAML template using its checked-in lint fixtures.

The workflow runs this only in the disposable CI checkout. Tests can call
render_variants() directly without replacing source files.
"""

import argparse
import json
import re
from pathlib import Path
from typing import Any

import chevron
import yaml

TEMPLATE_SUFFIXES = (".mustache.yaml", ".mustache.yml")


def _fixture_path(template: Path, root: Path) -> Path:
    # AdGuardHome.mustache.yaml -> .github/resources/AdGuardHome.mustache.config.json
    return (
        root
        / ".github"
        / "resources"
        / f"{template.name.rsplit('.', 1)[0]}.config.json"
    )


def _validate_context(
    template: str, context: dict[str, Any], fixture_path: Path
) -> None:
    """Ensure required Mustache keys are supplied instead of silently blanked."""
    for tag_type, tag in chevron.tokenizer.tokenize(template):
        if tag_type not in ("variable", "no escape", "section", "inverted section"):
            continue
        if tag == ".":
            continue
        key = tag.split(".", maxsplit=1)[0]
        if key not in context:
            msg = f"Missing Mustache key '{key}' in {fixture_path}"
            raise ValueError(msg)


def render_variants(template_path: Path, root: Path) -> list[str]:
    """Return all valid fixture expansions of one template, without writing files."""
    fixture = _fixture_path(template_path, root)
    if not fixture.is_file():
        msg = f"Mustache template requires a lint fixture: {fixture}"
        raise FileNotFoundError(msg)

    contents = json.loads(fixture.read_text(encoding="utf-8"))
    contexts = contents if isinstance(contents, list) else [contents]
    if not contexts or not all(isinstance(context, dict) for context in contexts):
        msg = f"Expected nonempty object/list of objects in {fixture}"
        raise ValueError(msg)

    source = template_path.read_text(encoding="utf-8")
    outputs = []
    for index, context in enumerate(contexts, start=1):
        _validate_context(source, context, fixture)
        rendered = chevron.render(source, context)
        if re.search(r"\{\{[#^/&{!]?", rendered):
            msg = f"Unexpanded Mustache token in {template_path}, fixture #{index}"
            raise ValueError(msg)
        # Parse the completed YAML, not the template with all variables removed.
        yaml.safe_load(rendered)
        outputs.append(rendered)
    return outputs


def render_all(root: Path, *, in_place: bool = False) -> dict[Path, list[str]]:
    """Render all templates and optionally replace them in a disposable CI checkout."""
    source = root / "data_safe_haven" / "resources"
    templates = sorted(
        path
        for path in source.rglob("*")
        if path.is_file() and path.name.endswith(TEMPLATE_SUFFIXES)
    )
    if not templates:
        msg = f"No Mustache YAML templates found under {source}"
        raise FileNotFoundError(msg)

    rendered = {path: render_variants(path, root) for path in templates}
    if in_place:
        for path, variants in rendered.items():
            path.write_text(variants[0], encoding="utf-8")
            for variant_index, output in enumerate(variants[1:], start=2):
                variant_path = path.with_name(
                    f"{path.stem}.variant-{variant_index}{path.suffix}"
                )
                variant_path.write_text(output, encoding="utf-8")
    return rendered


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[2]
    )
    parser.add_argument(
        "--in-place", action="store_true", help="Modify disposable CI working tree"
    )
    args = parser.parse_args()
    rendered = render_all(args.root.resolve(), in_place=args.in_place)
    print(  # noqa: T201
        f"Validated {len(rendered)} Mustache YAML templates "
        f"({sum(len(outputs) for outputs in rendered.values())} expansion variants)."
    )


if __name__ == "__main__":
    main()
