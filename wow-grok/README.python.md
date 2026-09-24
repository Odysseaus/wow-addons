# WoW Grok — Python bridge (draft)

This is the **Python rewrite** of the companion bridge (`bridge_py/`). The Lua addon under `addon/WoWGrok/` is unchanged. The Node bridge under `bridge/` remains until cutover.

**For players:** see **[docs/INSTALL-USERS.md](docs/INSTALL-USERS.md)** (Mac + Windows, no Node required).  
**GeForce Now / cloud WoW is not supported.**

## Quick start (developers)

```bash
cd wow-grok
python3 -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install pillow
python -m bridge_py --help
python -m unittest discover -s bridge_py/tests -v
```

First real run opens a local popup for your xAI API key and AddOns folder; values go only into `bridge_py/config.json` on your machine.

## Layout

```
bridge_py/          Python package (supervisor, protocol, xAI, capture stubs)
addon/WoWGrok/      Lua addon (unchanged)
bridge/             Node bridge (legacy until cutover)
docs/INSTALL-USERS.md
bridge_py/packaging.md
```

## Packaging

Separate Windows `.exe` and Mac `.app`/`.dmg` — see `bridge_py/packaging.md`.

## License

MIT (same as upstream wow-claude attribution in LICENSE / README).
