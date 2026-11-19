#!/usr/bin/env bash
#
# select-modules.sh — resolve selected module names into build specs.
#
# Usage: select-modules.sh <catalog.json> "<name1,name2>" [CUSTOM_MODULES_JSON]
#
# Emits one line per selected module:  name|url|ref|type
# Sources: the catalog file, plus ad-hoc entries in CUSTOM_MODULES_JSON
# (a JSON array of {name,url,ref,type}).
#
# Validation (fail BEFORE compile, actionable messages):
#   - selected names must exist in catalog or custom JSON
#   - only type=static is supported in the single-package build (for now)
#   - url must be https; name must match a safe pattern
#
set -euo pipefail

CATALOG="${1:?usage: select-modules.sh <catalog> <selected-names> [custom-json]}"
SELECTED="${2:-}"
CUSTOM="${3:-[]}"

python3 - "$CATALOG" "$SELECTED" "$CUSTOM" <<'PY'
import json, re, sys

catalog_path, selected_arg, custom_arg = sys.argv[1], sys.argv[2], sys.argv[3]
selected = [s.strip() for s in selected_arg.split(",") if s.strip()]
custom = json.loads(custom_arg)

with open(catalog_path, "r", encoding="utf-8") as f:
    catalog = {m["name"]: m for m in json.load(f)["modules"]}
custom_by_name = {}
for c in custom:
    for k in ("name", "url", "ref"):
        if k not in c:
            print(f"ERROR: custom module entry missing '{k}': {c}", file=sys.stderr)
            sys.exit(3)
    custom_by_name[c["name"]] = c

if not selected:
    sys.exit(0)

name_re = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
specs = []
for name in selected:
    if name in catalog:
        m = catalog[name]
        specs.append((name, m["url"], m["ref"], m.get("type", "static")))
    elif name in custom_by_name:
        c = custom_by_name[name]
        specs.append((c["name"], c["url"], c["ref"], c.get("type", "static")))
    else:
        print(
            f"ERROR: module '{name}' is neither in the catalog "
            f"({', '.join(sorted(catalog))}) nor in the custom modules JSON",
            file=sys.stderr,
        )
        sys.exit(3)

for name, url, ref, mtype in specs:
    if mtype != "static":
        print(
            f"ERROR: module '{name}' has type '{mtype}'. Dynamic (.so) modules "
            "are not supported in the single-package build yet. Choose a "
            "static module or request dynamic-module support.",
            file=sys.stderr,
        )
        sys.exit(4)
    if not url.startswith("https://"):
        print(f"ERROR: module '{name}': module URL must be https:// (got {url})", file=sys.stderr)
        sys.exit(5)
    if not name_re.match(name):
        print(f"ERROR: module '{name}': name must match {name_re.pattern}", file=sys.stderr)
        sys.exit(5)
    if not re.match(r"^[0-9A-Za-z][0-9A-Za-z._/-]*$", ref):
        print(f"ERROR: module '{name}': invalid ref '{ref}'", file=sys.stderr)
        sys.exit(5)

for name, url, ref, mtype in specs:
    print(f"{name}|{url}|{ref}|{mtype}")
PY
