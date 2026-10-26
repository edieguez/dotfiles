# Ghostty config

My terminal setup. Built around living in nvim, yazi and markdown most of the day, not around looking impressive in a screenshot (well, mostly).

## Layout

```
ghostty/
└── .config/ghostty/
    ├── config     # symlinked to ~/.config/ghostty/config
    ├── themes/
    │   └── Pure Black Vivid
    └── shaders/   # github.com/hackr-sh/ghostty-shaders, cloned in full
```

## Font

[JetBrains Mono](https://www.jetbrains.com/lp/mono/) at `12.5pt`. If it's missing:

```sh
brew install --cask font-jetbrains-mono
```

## Theme

`Pure Black Vivid` — true black background, saturated ANSI colors. It's a custom theme file in [`themes/`](.config/ghostty/themes/Pure%20Black%20Vivid), not one of Ghostty's bundled ones.

## Shader

`custom-shader` points at [`dither.glsl`](.config/ghostty/shaders/dither.glsl) from [hackr-sh/ghostty-shaders](https://github.com/hackr-sh/ghostty-shaders). That repo is cloned whole into `shaders/`, so switching looks is just pointing `custom-shader` at a different `.glsl` in there.

## Splits & navigation

Most of this is just Ghostty's own macOS defaults — no point overriding what already works:

| Key | Does what |
|---|---|
| `cmd+d` / `cmd+shift+d` | new split, right / down |
| `cmd+alt+←↑↓→` | move between splits |
| `cmd+ctrl+←↑↓→` | resize the focused split |
| `cmd+ctrl+=` | equalize split sizes |
| `cmd+shift+enter` | zoom / unzoom the split |
| `cmd+shift+↑` / `↓` | jump to previous / next shell prompt |

`ctrl+h/j/k/l` is deliberately left unbound here — those keys are for Neovim's own
window navigation. Ghostty has no multiplexer-aware integration for them (no
plugin bridges Ghostty splits and Neovim windows on the same keys), so binding
them at the Ghostty level just steals the keystroke before Neovim ever sees it.

## Quick terminal

`cmd+` `` ` `` drops a floating terminal down from the top of the screen, Quake-style, from any app. macOS will ask for Accessibility access the first time — that's normal, not a bug.

## Shell integration

`cursor,sudo,title,path`:

- cursor changes shape at the prompt
- `sudo` doesn't break terminfo
- window title follows whatever the shell is doing
- Ghostty's own CLI stays on `PATH` even if some init script stomps on it

## Window

- `window-save-state = always` — splits and tabs come back after a restart
- `8px` padding so text isn't glued to the edges
- `background-opacity 0.96` + blur, titlebar folded into the tab bar instead of sitting on top of it

## Left alone on purpose

Didn't bother configuring image previews, clickable links, or sane double-click word/path selection — Ghostty already does all of that by default, which covers yazi's image preview and most of what markdown writing needs day to day.
