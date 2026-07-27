#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
overlay_test_dir="$(mktemp -d)"
trap 'rm -rf "$overlay_test_dir"' EXIT

grep -Fq 'background: #000;' "$project_dir/browser/index.html"
grep -Fq '██████╗ ██╗   ██╗███████╗███████╗██████╗' \
    "$project_dir/browser/index.html"
if grep -Fq '<h1>Buzzbox</h1>' "$project_dir/browser/index.html"; then
    echo "The obsolete browser welcome card is still present." >&2
    exit 1
fi

grep -Fq 'ENV GTK_THEME=Buzzbox' "$project_dir/Dockerfile"
grep -Fq \
    'ENV G_RESOURCE_OVERLAYS=/org/gtk/libgtk=/usr/share/buzzbox/gtk-overlay' \
    "$project_dir/Dockerfile"
grep -Fq \
    'COPY gtk/Buzzbox /usr/share/themes/Buzzbox' \
    "$project_dir/Dockerfile"
grep -Fq \
    'COPY gtk/generate-resource-overlay.py /tmp/generate-gtk-resource-overlay.py' \
    "$project_dir/Dockerfile"

python3 "$project_dir/gtk/generate-resource-overlay.py" \
    "$project_dir/openbox/theme" "$overlay_test_dir"
for control in minimize maximize restore close; do
    control_path="$overlay_test_dir/icons/16x16/status/window-${control}-symbolic.symbolic.png"
    test -s "$control_path"
    python3 -c \
        'import pathlib, sys; assert pathlib.Path(sys.argv[1]).read_bytes().startswith(b"\x89PNG\r\n\x1a\n")' \
        "$control_path"
done

grep -Fq '"system_theme": 1' "$project_dir/Dockerfile"
grep -Fq 'popover.background.menu' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'background-color: #020303;' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'window.background.csd decoration' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'decoration:not(:backdrop)' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'headerbar.header-bar.titlebar' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'border-radius: 0;' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'padding-right: 4px;' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'button.titlebutton:backdrop' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'caret-color: #d7d72e;' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fq 'color: #dc143c;' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/gtk.css"
grep -Fxq 'gtk-font-name = Noto Sans 9' \
    "$project_dir/gtk/Buzzbox/gtk-3.0/settings.ini"
test "$(grep -Fc '<name>Noto Sans</name>' "$project_dir/openbox/rc.xml")" -eq 6
test "$(grep -Fc '<size>9</size>' "$project_dir/openbox/rc.xml")" -eq 6

if grep -Fq '"BrowserThemeColor"' "$project_dir/Dockerfile"; then
    echo "BrowserThemeColor still overrides the GTK Chrome theme." >&2
    exit 1
fi
if grep -Fq -- '--pack-extension=' "$project_dir/Dockerfile"; then
    echo "The obsolete Chrome extension theme is still packaged." >&2
    exit 1
fi
