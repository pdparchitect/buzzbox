#!/bin/bash
# Patch KasmVNC web assets to remove branding and apply customisations.
# Run once after installing the kasmvnc .deb package.
set -euo pipefail

WWW=/usr/share/kasmvnc/www

# 1. Inject custom.css link, rebrand title, strip icon links from all HTML files.
find "$WWW" -maxdepth 1 -name '*.html' -exec sed -i \
    -e 's|</head>|<link rel="stylesheet" href="./assets/custom.css"></head>|' \
    -e 's|<title>[^<]*</title>|<title>Buzzbox</title>|' \
    -e 's|<link[^>]*rel="icon"[^>]*>||g' \
    -e 's|<link[^>]*rel="apple-touch-icon"[^>]*>||g' \
    {} +

# 2. Replace the "KasmVNC" brand string in the UI JavaScript.
find "$WWW/assets" -name 'ui-*.js' -exec sed -i \
    -e 's|"KasmVNC"|"Buzzbox"|g' \
    {} +

echo "[kasm-patch] KasmVNC UI patched successfully"
