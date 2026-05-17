# mistral-vibe-patches

Bugfix patches for [Mistral Vibe](https://github.com/mistralai/mistral-vibe), the CLI coding agent
by Mistral AI.

**Author:** [@doutorprestes](https://github.com/doutorprestes)

These patches are derivative works of Mistral Vibe, Copyright Mistral AI — distributed under
[Apache 2.0](LICENSE). See each `.patch` file for the `Signed-off-by` line.

## Patches

| # | Patch | Affects | Issue |
|---|-------|---------|-------|
| 1 | **config-merge** | `_settings.py`, `_harness_manager.py` | [#657](https://github.com/mistralai/mistral-vibe/issues/657) |
| 2 | **reasoning-unset** | `mistral.py` (MistralBackend) | — |

### Patch 1 — User config takes precedence over project config

When both `~/.vibe/config.toml` (user) and `.vibe/config.toml` (project) exist, the
user-level configuration is completely ignored. Custom `[[models]]` definitions and
`active_model` set by the user are silently discarded.

**Root cause:** `HarnessFilesManager.config_file` returns the project config when
the working directory is trusted, without merging it with the user-level config.
The `TomlFileSettingsSource._load_toml()` method loads only that single file.

**Fix:** The `user_config_file` property is moved next to `config_file` for
discoverability, keeping its path as `~/.vibe/config.toml` (the `.vibe/`
subdirectory is a project-level convention, not a user-level one). When both
"user" and "project" sources are enabled, the TOML loader now loads both files
and merges them with user settings taking precedence. Lists such as `models`
and `providers` are merged by their identifiers (alias / name) rather than
being fully replaced.

### Patch 2 — Omit `reasoning_effort` and `reasoning_content` when thinking is off

Models like `devstral-small-latest` reject requests that include `reasoning_effort`
in the JSON payload or `reasoning_content` in the message history. Previously, even
when the model had `thinking="off"`, switching from a thinking model mid-session
left stale `reasoning_content` fields in accumulated messages.

**Root causes:**

1. `MistralBackend.complete()` passed `reasoning_effort=None` to the SDK, which
   serialized as `"reasoning_effort": null` in the request body.
2. Neither `complete()` nor `complete_streaming()` stripped `reasoning_content`
   from assistant messages before sending them to the API.
3. The first patch attempt used `model_copy(exclude=...)` which is not supported
   by pydantic v2 — the `exclude` parameter does not exist on `model_copy`,
   causing a silent TypeError.

**Fix:**

- Use the Mistral SDK's `UNSET` sentinel instead of `None` when `thinking="off"`,
  which omits `reasoning_effort` entirely from the request body.
- Strip `reasoning_content` from all messages in **both** `complete()` and
  `complete_streaming()` when `thinking="off"`, using the correct
  `model_copy(update={"reasoning_content": None}, deep=True)` pattern.

---

## Usage

```bash
# 1. Download
curl -sSfL -O https://raw.githubusercontent.com/doutorprestes/mistral-vibe-patches/main/apply.sh
chmod +x apply.sh

# 2. Apply all patches
./apply.sh

# 3. Verify
cd ~/your-project  # where .vibe/config.toml exists
vibe -p "What model am I using?"
```

### Options

```bash
./apply.sh --help
./apply.sh --path /custom/site-packages
./apply.sh --reverse        # revert all patches
./apply.sh --only 1         # apply only patch 1
```

### Reverting

```bash
./apply.sh --reverse
```

Backups of the original files are created with `.bak` extension alongside the
original files.

---

## How it works

The `apply.sh` script:

1. Auto-detects the Vibe installation path (supports `uv`, `pipx`, and Homebrew)
2. Creates `.bak` backups of every file that will be patched
3. Applies the unified diffs using `patch -p1`
4. Verifies the patches were applied correctly (including path sanity checks)

You can also inspect each `.patch` file and apply it manually:

```bash
cd $(python3 -c "import vibe; print(vibe.__path__[0])")/..
patch -p1 < patches/001-config-merge.patch
patch -p1 < patches/002-reasoning-unset.patch
```

## Compatibility

| Vibe version | Status |
|-------------|--------|
| v2.9.6 | Tested |
| v2.9.3 | Should work |
| Earlier | Untested |

## Related issues

- [#657](https://github.com/mistralai/mistral-vibe/issues/657) — Custom models in
  config.toml not respected
- [#585](https://github.com/mistralai/mistral-vibe/issues/585) — devstral-2 400
  Bad Request
- [#617](https://github.com/mistralai/mistral-vibe/issues/617) — devstral-2
  Invalid model: mistral-medium-3.5

## License

These patches are provided under the same license as Mistral Vibe
([Apache 2.0](LICENSE)).