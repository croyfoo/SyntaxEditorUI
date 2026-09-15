#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 OUTPUT_DIRECTORY [HOSTING_BASE_PATH]" >&2
    exit 64
fi

output_dir=$1
hosting_base_path=${2:-}
hosting_base_path=${hosting_base_path%/}
repo_root=$(cd "$(dirname "$0")/.." && pwd)

# A Pages artifact must not retain files from an earlier documentation build.
if [[ -e "$output_dir" ]]; then
    echo "Output directory already exists: $output_dir" >&2
    exit 64
fi
mkdir -p "$(dirname "$output_dir")"
mkdir "$output_dir"
build_root=

cleanup() {
    local exit_status=$?
    local cleanup_status=0
    if (( exit_status != 0 )); then
        rm -rf -- "$output_dir" || cleanup_status=$?
    fi
    if [[ -n "$build_root" ]]; then
        rm -rf -- "$build_root" || cleanup_status=$?
    fi
    if (( exit_status != 0 )); then
        exit "$exit_status"
    fi
    exit "$cleanup_status"
}
trap cleanup EXIT

resolved_output_dir=$(cd "$output_dir" && pwd)
output_dir=$resolved_output_dir
build_root=$(mktemp -d "${TMPDIR:-/tmp}/syntax-editor-docs.XXXXXX")

cp -R "$repo_root/Documentation/SyntaxEditorUI.docc" "$build_root/Documentation.docc"
python3 - "$build_root/Documentation.docc" "$hosting_base_path" <<'PY'
import pathlib
import sys

for page in pathlib.Path(sys.argv[1]).glob("*.md"):
    text = page.read_text()
    for platform in ("uikit", "appkit"):
        text = text.replace(f"](/{platform}/", f"]({sys.argv[2]}/{platform}/")
    page.write_text(text)
PY

xcrun docc convert "$build_root/Documentation.docc" \
    --output-dir "$build_root/Documentation.doccarchive" \
    --hosting-base-path "$hosting_base_path" \
    --fallback-display-name SyntaxEditorUI \
    --fallback-bundle-identifier dev.lynnswap.SyntaxEditorUI.Documentation \
    --warnings-as-errors
cp -R "$build_root/Documentation.doccarchive/." "$output_dir/"

# DocC's technology root is below /documentation, not the site's base URL.
cat > "$output_dir/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=documentation/syntaxeditorui/">
<title>SyntaxEditorUI Documentation</title>
<a href="documentation/syntaxeditorui/">Open documentation</a>
</html>
HTML

# The compiler still decides which modules the umbrella exports. This allowlist
# permits its local source modules without exposing imported dependency APIs.
reexported_modules=$(python3 - "$repo_root/Sources" <<'PY'
import pathlib
import sys

print(",".join(sorted(path.name for path in pathlib.Path(sys.argv[1]).iterdir() if path.is_dir())))
PY
)
architecture=$(uname -m)

for platform in uikit appkit; do
    case "$platform" in
        uikit)
            destination='generic/platform=iOS Simulator'
            sdk=iphonesimulator
            configuration_dir=Debug-iphonesimulator
            catalog=UIKit
            target="$architecture-apple-ios$(xcrun --sdk "$sdk" --show-sdk-version)-simulator"
            ;;
        appkit)
            destination='generic/platform=macOS'
            sdk=macosx
            configuration_dir=Debug
            catalog=AppKit
            target="$architecture-apple-macos$(xcrun --sdk "$sdk" --show-sdk-version)"
            ;;
    esac

    cp -R "$repo_root/Documentation/$catalog.docc" "$build_root/$catalog.docc"
    cp "$repo_root/Documentation/Shared/"*.md "$build_root/$catalog.docc/"

    # Build the product, then document its exported API. Running docbuild on the
    # package also compiles third-party catalogs and applies our DocC flags to them.
    xcodebuild build \
        -workspace "$repo_root/SyntaxEditorUI.xcworkspace" \
        -scheme SyntaxEditorUI \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$build_root/$platform" \
        -clonedSourcePackagesDirPath "$build_root/SourcePackages" \
        "ARCHS=$architecture" \
        CODE_SIGNING_ALLOWED=NO

    products="$build_root/$platform/Build/Products/$configuration_dir"
    graphs="$build_root/$platform/SymbolGraphs"
    mkdir -p "$graphs"
    module_map_flags=()
    for module_map in "$build_root/$platform/Build/Intermediates.noindex/GeneratedModuleMaps"*/*.modulemap; do
        module_map_flags+=(-Xcc "-fmodule-map-file=$module_map")
    done

    xcrun swift-symbolgraph-extract \
        -module-name SyntaxEditorUI \
        -target "$target" \
        -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" \
        -I "$products" \
        -F "$products/PackageFrameworks" \
        "${module_map_flags[@]}" \
        "-experimental-allowed-reexported-modules=$reexported_modules" \
        -skip-synthesized-members \
        -output-dir "$graphs"

    # DocC does not warn about missing comments. Require contracts for our API,
    # while recognizing implementations of external requirements from compiler metadata.
    python3 - "$graphs/SyntaxEditorUI.symbols.json" "$repo_root/Sources" "$platform" <<'PY'
import json
import pathlib
import sys
import urllib.parse

graph = json.loads(pathlib.Path(sys.argv[1]).read_text())
source_root = pathlib.Path(sys.argv[2]).resolve()
symbols = []
for symbol in graph["symbols"]:
    location = symbol.get("location")
    if location:
        source = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(location["uri"]).path)).resolve()
        if source.is_relative_to(source_root):
            symbols.append(symbol)
if not symbols:
    raise SystemExit("No authored public symbols were extracted.")
authored_identifiers = {symbol["identifier"]["precise"] for symbol in symbols}
external_implementations = set()
for relationship in graph["relationships"]:
    origin = relationship.get("sourceOrigin", {}).get("identifier")
    if relationship["kind"] == "overrides":
        origin = relationship["target"]
    if origin and origin not in authored_identifiers:
        external_implementations.add(relationship["source"])
undocumented = [
    symbol
    for symbol in symbols
    if not any(line["text"].strip() for line in symbol.get("docComment", {}).get("lines", []))
]
missing = [
    ".".join(symbol["pathComponents"])
    for symbol in undocumented
    if symbol["identifier"]["precise"] not in external_implementations
]
if missing:
    raise SystemExit("Missing public documentation:\n" + "\n".join(sorted(missing)))
print(
    f"{sys.argv[3]}: {len(symbols) - len(undocumented)} authored public symbols documented; "
    f"{len(undocumented)} external API implementations without additional comments."
)
PY

    archive="$build_root/$platform/SyntaxEditorUI.doccarchive"
    xcrun docc convert "$build_root/$catalog.docc" \
        --additional-symbol-graph-dir "$graphs" \
        --output-dir "$archive" \
        --hosting-base-path "$hosting_base_path/$platform" \
        --fallback-display-name SyntaxEditorUI \
        --fallback-bundle-identifier "dev.lynnswap.SyntaxEditorUI.$catalog" \
        --warnings-as-errors \
        --experimental-documentation-coverage

    test -f "$archive/documentation/syntaxeditorui/index.html"
    test -f "$archive/documentation/syntaxeditorui/syntaxeditormodel/index.html"
    test -f "$archive/documentation/syntaxeditorui/syntaxeditorview/index.html"
    cp -R "$archive" "$output_dir/$platform"
done

echo "Documentation site: $output_dir"
