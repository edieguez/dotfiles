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

## Changes on top of Oh my Tmux

- Prefix is Ctrl+B only. Ctrl+A is "line start" in zsh and "increment" in Neovim.
- `mode-keys vi`, 50000 lines of history.
- Plugins (installed by tpm on first start): tmux-resurrect and tmux-continuum
  (sessions saved every 15 min and restored on server start), vim-tmux-navigator.

| Key | Does what |
|---|---|
| `ctrl+h/j/k/l` | move between panes, and Neovim windows inside them |
| `ctrl+l` | in a shell with no pane to the right: clear screen and scrollback |
| `<prefix> C-k` | clear screen and scrollback of this pane |
| `<prefix> {` / `}` | move window left / right |

The Ghostty shortcuts that drive these are listed in
[`../ghostty/README.md`](../ghostty/README.md).
