# WoW Grok — Python bridge (developers)

This is the **Python rewrite** of the companion bridge (`bridge_py/`). The Lua addon under `addon/WoWGrok/` is unchanged. The Node bridge under `bridge/` remains until cutover.

**Players:** use the packaged app — [docs/INSTALL-USERS.md](docs/INSTALL-USERS.md) (no Python / pip / npm).  
**Developers / from source:** [docs/DEV.md](docs/DEV.md).  
**GeForce Now / cloud WoW is not supported.**

```bash
cd wow-grok
python3 -m venv .venv && source .venv/bin/activate
pip install pillow
python -m bridge_py --help
python -m unittest discover -s bridge_py/tests -v
```

## Packaging

Separate Windows `.exe` and Mac `.app`/`.dmg` — see `bridge_py/packaging.md`.

## License

MIT (same as upstream wow-claude attribution in LICENSE / README).
