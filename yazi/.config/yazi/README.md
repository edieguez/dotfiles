# Yazi configuration

## Plugins

`package.toml` lists the plugins and pins their versions; the `plugins/` folder is not versioned. Install them with:

```sh
ya pkg install
```

- `yazi-rs/plugins:full-border`
- `yazi-rs/plugins:git`
- `yazi-rs/plugins:mount`
- `yazi-rs/plugins:toggle-pane`

Add a plugin with `ya pkg add <repo>:<plugin>` and update all of them with `ya pkg upgrade`. Both commands rewrite
`package.toml`; commit it afterwards.
