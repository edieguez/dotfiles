# tmux

User config for [Oh my Tmux](https://github.com/gpakosz/.tmux). Install the base first:

```sh
git clone https://github.com/gpakosz/.tmux.git ~/.tmux
ln -s .tmux/.tmux.conf ~/.tmux.conf
cd ~/.dotfiles && stow tmux
```

Ghostty starts `~/.config/ghostty/tmux-main`, which runs the tmux server as a launchd
job (`.config/tmux/tmux-server.plist`). macOS 27 kills every process in an app's
coalition shortly after the app quits, so a server started from Ghostty's shell
would die with it. To stop the job: `launchctl bootout gui/$(id -u)/tmux-server`.

After `brew upgrade tmux` the old server keeps running in memory while new clients use
the new binary, which can misbehave. Restart it (this kills every session; the next
Ghostty window creates a fresh `main`):

```sh
launchctl kickstart -k gui/$(id -u)/tmux-server
```

## Changes on top of Oh my Tmux

- Prefix is Ctrl+B only. Ctrl+A is "line start" in zsh and "increment" in Neovim.
- `mode-keys vi`, 50000 lines of history.
- One plugin, installed by tpm on first start: vim-tmux-navigator. Sessions are
  not saved across reboots; the launcher just creates a fresh `main`.

| Key | Does what |
|---|---|
| `ctrl+h/j/k/l` | move between panes, and Neovim windows inside them |
| `ctrl+l` | in a shell with no pane to the right: clear screen and scrollback |
| `<prefix> C-k` | clear screen and scrollback of this pane |
| `<prefix> {` / `}` | move window left / right |

The Ghostty shortcuts that drive these are listed in
[`../ghostty/README.md`](../ghostty/README.md).

## Status bar

The right side shows the weather from [wttr.in](https://wttr.in) via `.config/tmux/weather.sh`,
which caches the answer for 30 minutes in `~/.cache/tmux-weather`. Location is guessed from
the IP address; to pin it: `tmux set-environment -g WTTR_LOCATION Mexico+City`.
