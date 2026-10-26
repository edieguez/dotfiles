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
