#!/usr/bin/env python3
"""Map former platform routes to the canonical routes emitted by DocC."""

import argparse
import html
import json
from pathlib import Path


def read_pages(archive):
    data = archive / "data"
    return {
        "/" + path.relative_to(data).with_suffix("").as_posix(): json.loads(path.read_text())
        for path in sorted((data / "documentation").rglob("*.json"))
    }


def generate_redirects(archive, legacy_root, output, hosting_base_path):
    pages = read_pages(archive)
    symbol_paths = {}
    for path, page in pages.items():
        identifier = page.get("metadata", {}).get("externalID")
        if identifier:
            if identifier in symbol_paths and symbol_paths[identifier] != path:
                raise ValueError(f"Multiple canonical routes for {identifier}")
            symbol_paths[identifier] = path

    module = "/documentation/syntaxeditorui"
    redirects = {"index.html": module}
    shared_guides = ("gettingstarted", "editing", "languagesandthemes", "migration")

    for platform in ("uikit", "appkit"):
        legacy_pages = read_pages(legacy_root / f"{platform}.doccarchive")
        if not legacy_pages:
            raise ValueError(f"No legacy routes were generated for {platform}")

        paths = {}
        collections = []
        for old_path, page in legacy_pages.items():
            identifier = page.get("metadata", {}).get("externalID")
            if identifier:
                if identifier not in symbol_paths:
                    raise ValueError(f"No current symbol for {platform}{old_path}: {identifier}")
                paths[old_path] = symbol_paths[identifier]
            elif page.get("metadata", {}).get("role") == "collectionGroup":
                collections.append(old_path)
            else:
                raise ValueError(f"Unrecognized legacy page: {platform}{old_path}")

        # Collection pages have no symbol ID. Their containing symbol does.
        for old_path in collections:
            parent = old_path.rsplit("/", 1)[0]
            while parent not in paths:
                if not parent:
                    raise ValueError(f"No containing symbol for {platform}{old_path}")
                parent = parent.rsplit("/", 1)[0]
            paths[old_path] = paths[parent] + old_path[len(parent):]

        for guide in (*shared_guides, f"{platform}integration"):
            path = f"{module}/{guide}"
            paths[path] = path
        paths[module] = f"{module}/{platform}integration"

        for old_path, target in paths.items():
            if target not in pages:
                raise ValueError(f"No current page for {platform}{old_path}: {target}")
            redirects[f"{platform}{old_path}/index.html"] = target
        print(f"{platform}: {len(paths)} legacy guide and API routes mapped.")

    base = "/" + hosting_base_path.strip("/") if hosting_base_path.strip("/") else ""
    for relative_path, route in redirects.items():
        destination = base + route.rstrip("/") + "/"
        target = html.escape(destination, quote=True)
        script_target = json.dumps(destination).replace("<", "\\u003c")
        path = output / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<title>SyntaxEditorUI Documentation</title>\n'
            f'<script>location.replace({script_target} + location.search + location.hash);</script>\n'
            f'<noscript><meta http-equiv="refresh" content="0; url={target}"></noscript>\n'
            f'</head>\n<body><a href="{target}">Open documentation</a></body>\n</html>\n'
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("legacy_root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("hosting_base_path", nargs="?", default="")
    args = parser.parse_args()
    generate_redirects(args.archive, args.legacy_root, args.output, args.hosting_base_path)


if __name__ == "__main__":
    main()
