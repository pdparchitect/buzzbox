# Image size and the graphical stack

Buzzbox is a browser-accessible Buzz desktop, so a graphical stack is not
optional here the way it might appear to be in a headless node. This document
records what that stack costs, why it is there, and which parts have been
trimmed.

Regenerate every number here with:

```bash
make build
make size-report
```

## Measured composition

`pdparchitect/buzzbox:local`, **4.28 GB** (4082 MiB) uncompressed:

| Layer                                    |   Size |
| ---------------------------------------- | -----: |
| Codex, Claude Code, and the ACP adapters | 1.31 GB |
| Core apt baseline, including GTK/WebKit   | 1.22 GB |
| Google Chrome                             |  441 MB |
| Goose                                     |  299 MB |
| Node.js 24                                |  198 MB |
| Desktop apt layer                         |  191 MB |
| Buzz `.deb`                               |  173 MB |
| MinIO                                     |  111 MB |
| Docker and GitHub CLIs                    | 89.2 MB |
| Ubuntu base                               | 78.1 MB |

The graphical substrate is **1265 MiB, or 31.0% of the image**. It is not the
largest contributor: the three coding CLIs alone are larger.

Measured as a dependency closure — what apt would remove if the desktop
top-level packages were purged — so transitively shared libraries are counted
once and attributed correctly:

| Component                             |     Size |
| ------------------------------------- | -------: |
| Chrome                                | 413.6 MiB |
| Mesa and LLVM software GL             | 186.2 MiB |
| Buzz `.deb`                           | 162.7 MiB |
| Fonts and icon themes                 | 144.3 MiB |
| WebKitGTK, Buzz Desktop's runtime     | 121.5 MiB |
| GTK, Pango, GStreamer                 |  40.9 MiB |
| KasmVNC and its perl dependencies     |  36.1 MiB |
| Ghostscript, via openbox/tint2 imlib2 |  26.3 MiB |
| kitty terminal                        |  18.8 MiB |
| systemd/udev/dbus session             |  18.8 MiB |
| X11 server and utilities              |   7.8 MiB |
| Openbox, tint2, picom                 |   5.2 MiB |
| Other shared libraries                |  83.1 MiB |

Plus 13 MB of non-package assets: the cortile binary, the patched KasmVNC web
client, the Openbox theme, and the wallpaper.

Two notes on reading this table:

- The Buzz `.deb` appears in full because `buzz-desktop` links WebKitGTK, so
  purging the GTK stack takes the package with it. Only the `buzz-desktop`
  binary — 96 MiB of the 163 — is genuinely graphical; the headless `buzz`,
  `buzz-acp`, `buzz-agent`, and `buzz-dev-mcp` tools in the same package are
  not. Attributing only the GUI binary puts the graphical share at about 29%.
- Buzzbox installs GTK and WebKit in its **core** stage, for Buzz Desktop,
  rather than in the desktop stage. That is why the desktop apt layer here is
  191 MB while Buzznode's is 466 MB: the shared libraries are simply paid for
  earlier.

**The desktop shell itself is nearly free.** Openbox, tint2, picom, the X
utilities, and cortile together are about 22 MiB. The weight is Chrome, the
WebKit runtime Buzz Desktop needs, software GL, and fonts.

## Why the stack is this size

Buzzbox exists to put a Buzz desktop in a browser, so the graphical stack is
the product, not an accessory. Three things dominate it:

**Buzz Desktop's runtime.** `buzz-desktop` is a Tauri application: a 96 MiB
binary plus 121.5 MiB of WebKitGTK and JavaScriptCore. That is the price of
shipping the actual desktop client, and Buzznode's decision to extract only the
headless binaries from the same `.deb` is what lets it skip both.

**Software GL.** There is no GPU in the container, so Mesa's llvmpipe renderer
and LLVM behind it — 186 MiB — do the rasterising for Chrome, WebKit, and
picom.

**Chrome and fonts.** Chrome is the secondary browser for documentation and
login flows; fonts are what keep the desktop legible.

## Computer use

Buzzbox ships the same computer-use toolchain as Buzznode — `scrot` for screen
capture, `xdotool` for input injection, `wmctrl` and Openbox for window
management, Chrome as a target application, and KasmVNC so a human can watch
the same `:1` display live.

The forward-looking case for that toolchain is stronger in Buzznode, which is
one persistent computer for one agent with its own volumes, browser profile,
and login state — the natural unit for a computer-use session. Buzzbox is a
workspace client that also happens to run agents, so treat its graphical stack
as serving Buzz Desktop first. See Buzznode's `IMAGE-SIZE.md` for that
rationale in full.

It does mean the two images stay deliberately aligned: same window manager,
same panel, same screenshot and input tools, same fonts. An agent behaviour
developed against one desktop transfers to the other.

## What was trimmed

KasmVNC supplies its own X server, so the packages Ubuntu ships for driving
real display hardware were never reachable:

| Removed              | Why                                                                |
| -------------------- | ------------------------------------------------------------------ |
| `xorg` metapackage   | Pulls `xserver-xorg-core`, input/video drivers, `keyboard-configuration`, and `udev` for hardware the container does not have. |
| `x11-xserver-utils`  | Its only consumer would be the `xrdb` call in KasmVNC's generated `xstartup`, and `xstartup` is replaced with `exec openbox-session`. It also drags in `cpp`/`gcc-13`. |

Together this removed about 86 MiB. `systemd` remains in Buzzbox — PostgreSQL
and the D-Bus user session require it — which is why the saving here is smaller
than Buzznode's.

`xauth`, `xkb-data`, `x11-xkb-utils`, and `xfonts-base` are now listed
explicitly in the Dockerfile. The first three are `kasmvncserver` dependencies
and the fourth supplies the core font path Xvnc is started with; naming them
means no future autoremove can take them out.

Verified after the change: Xvnc, Openbox, and tint2 start; 967 core fonts
resolve; `scrot`, `xdotool`, and `wmctrl` work; Chrome launches and maps a
window; KasmVNC serves on 6901; and `make check` and the `make smoke`
assertions pass, including the relay, PostgreSQL, Redis, MinIO, and
`buzz-desktop` checks.

## What is deliberately kept

| Kept                       |     Size | Reason                                                                 |
| -------------------------- | -------: | ---------------------------------------------------------------------- |
| WebKitGTK                  | 122 MiB | Buzz Desktop links it. Removing it removes the product.                |
| Chrome                     | 414 MiB | Login flows and documentation today, computer-use target tomorrow.      |
| Mesa and LLVM software GL  | 186 MiB | Hard dependency of `kasmvncserver`, `picom`, and `libgbm1`, and the renderer for WebKit with no GPU present. |
| Fonts and icon themes      | 144 MiB | Desktop legibility, and screenshot legibility for vision models.        |
| Ghostscript chain          |  26 MiB | Structural: `openbox`'s `libobrender32v5` and `tint2` need imlib2, which needs `libspectre1`, which needs `libgs10`. Dropping `feh` alone frees only 10 MiB. |

## Compression

All figures are uncompressed on-disk size. Registry transfer is roughly 40–50%
of these, and Chrome compresses worse than the library and font bytes, so its
share of a `docker pull` is higher than its share here.
