# Contributing to WoW Grok

Python companion (`bridge_py/`) + Lua addon (`addon/WoWGrok/`). Players use the packaged Mac/Windows executable — see [docs/INSTALL-USERS.md](docs/INSTALL-USERS.md).

## Layout

```
addon/WoWGrok/     Lua addon (bundled into the frozen app)
bridge_py/         Python bridge, first-run installer, packaging specs
docs/              Player + developer docs
```

## Developers

See [docs/DEV.md](docs/DEV.md). Quick check:

```bash
cd wow-grok
python3 -m venv .venv && source .venv/bin/activate
pip install pillow
python -m unittest discover -s bridge_py/tests -v
```

## License / attribution

MIT. Preserve upstream [wow-claude](https://github.com/chelinho139/wow-claude) attribution in [LICENSE](LICENSE).
