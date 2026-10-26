# Ghostty config

Ghostty is only the window. Every OS window runs tmux, which owns tabs, splits and
session persistence (see [`../tmux/README.md`](../tmux/README.md)).

## Layout

```
ghostty/
└── .config/ghostty/
    ├── config       # symlinked to ~/.config/ghostty/config
    ├── tmux-main    # what every window runs: attach or join session "main"
    ├── themes/
    │   └── Pure Black Vivid
    └── shaders/
        └── cursor-smear.glsl
```

Install with `cd ~/.dotfiles && stow ghostty tmux`. The `tmux` package is required:
`tmux-main` starts the tmux server from its launchd plist so the server outlives
Ghostty (macOS 27 kills every process in an app's coalition when the app quits).

## Windows and sessions

The first Ghostty window attaches to tmux session `main`. Every further window
creates a new session in the `main` group: same windows, own current window and
scroll position. Those extra sessions are destroyed when their window closes.

Cmd+Q is Ghostty's own quit. The tmux server and all its windows survive; the
next launch reattaches. `confirm-close-surface` is off because tmux is always
"still running".

## Shortcuts

All of these send a tmux key sequence (prefix is Ctrl+B). Default macOS Ghostty
bindings that are not listed here still work.

| Key | tmux | Does what |
|---|---|---|
| `ctrl+1..9` | `<prefix> 1..9` | go to window N |
| `cmd+[` / `cmd+]` | `<prefix> C-h` / `C-l` | previous / next window |
| `ctrl+tab` | `<prefix> Tab` | last window |
| `cmd+shift+←` / `→` | `<prefix> {` / `}` | move window left / right |
| `cmd+t` | `<prefix> c` | new window |
| `cmd+shift+r` | `<prefix> ,` | rename window |
| `cmd+d` / `cmd+shift+d` | `<prefix> "` / `%` | split below / right |
| `cmd+shift+enter` | `<prefix> z` | zoom / unzoom pane |
| `cmd+w` | `<prefix> x` | close pane (asks) |
| `cmd+k` | `<prefix> C-k` | clear screen and scrollback |
| `cmd+f` | `<prefix> [ ?` | search the scrollback |
| `cmd+shift+o` | `<prefix> s` | session switcher |
| `cmd+shift+n` | `<prefix> C-c` | new session |

`ctrl+h/j/k/l` move between tmux panes and Neovim windows alike
(vim-tmux-navigator). `ctrl+l` in a shell with no pane to its right clears the
screen instead.

## Font

[JetBrains Mono](https://www.jetbrains.com/lp/mono/) at `12.5pt`, thickened,
with 6% extra line height. If it's missing:

```sh
brew install --cask font-jetbrains-mono
```

## Theme and shader

`Pure Black Vivid` is a custom theme in [`themes/`](.config/ghostty/themes/Pure%20Black%20Vivid):
true black background, saturated ANSI colors. `custom-shader` points at
[`cursor-smear.glsl`](.config/ghostty/shaders/cursor-smear.glsl), which trails the
cursor when it jumps.

## Keyboard

`macos-option-as-alt = right`: the right Option key is Alt (Meta) for the terminal,
the left one keeps typing macOS special characters.
