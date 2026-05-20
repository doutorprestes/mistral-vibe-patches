# mistral-vibe-patches

Bugfix patches for [Mistral Vibe](https://github.com/mistralai/mistral-vibe), the CLI coding agent by Mistral AI.

**Author:** [@doutorprestes](https://github.com/doutorprestes)

These patches are derivative works of Mistral Vibe, Copyright Mistral AI — distributed under [Apache 2.0](LICENSE). See each `.patch` file for the `Signed-off-by` line.

## Patches

| # | Patch | Affects | Issue |
|---|-------|---------|-------|
| 1 | **config-merge** | `_settings.py` | [#657](https://github.com/mistralai/mistral-vibe/issues/657) |
| 2 | **reasoning-unset** | `mistral.py` | — |

### Patch 1 — User config takes precedence over project config

When both `~/.vibe/config.toml` (user) and `.vibe/config.toml` (project) exist, the user-level configuration is completely ignored. Custom `[[models]]` definitions and `active_model` set by the user are silently discarded.

**Root cause:** `HarnessFilesManager.config_file` returns only the project config when the working directory is trusted. `TomlFileSettingsSource._load_toml()` loads that single file, never consulting the user-level config.

**Fix:** When both `"user"` and `"project"` sources are enabled, `_load_toml()` now loads both files and merges them with user settings taking precedence. The new `_deep_merge_preserving_lists()` merges `[[models]]` by `alias` and `[[providers]]` by `name` rather than replacing the entire list.

### Patch 2 — Omit `reasoning_effort` and `reasoning_content` when thinking is off

Models like `devstral-small-latest` reject requests that include `reasoning_effort` in the payload or `reasoning_content` in the message history. Even with `thinking="off"`, switching from a thinking model mid-session left stale `reasoning_content` fields in accumulated messages.

**Root causes:**

1. `MistralBackend.complete()` passed `reasoning_effort=None` to the SDK, which serialized as `"reasoning_effort": null` in the request body.
2. Neither `complete()` nor `complete_streaming()` stripped `reasoning_content` from assistant messages before sending them to the API.
3. The first patch attempt used `model_copy(exclude=...)` — pydantic v2 does not support `exclude` on `model_copy`, causing a silent TypeError.

**Fix:**

- Use the Mistral SDK's `UNSET` sentinel instead of `None` when `thinking="off"`, which omits `reasoning_effort` entirely from the request body.
- Strip `reasoning_content` from all messages in both `complete()` and `complete_streaming()` when `thinking="off"`, using `model_copy(update={"reasoning_content": None}, deep=True)`.

## Usage

```bash
# 1. Download
curl -sSfL -O https://raw.githubusercontent.com/doutorprestes/mistral-vibe-patches/main/apply.sh
chmod +x apply.sh

# 2. Apply all patches
./apply.sh

# 3. Verify
cd ~/your-project
vibe -p "What model am I using?"
```

### Options

```
./apply.sh --help                 Show this help
./apply.sh --path /custom/dir     Explicit site-packages path
./apply.sh --reverse              Revert all applied patches
./apply.sh --only 1               Apply only patch 1
./apply.sh --version              Show version
```

### Reverting

```bash
./apply.sh --reverse
```

Backups of the original files are created with `.bak` extension alongside the original files.

## How it works

The `apply.sh` script:

1. Auto-detects the Vibe installation path (supports `uv`, `pipx`, and Homebrew)
2. Creates `.bak` backups of every file that will be patched
3. Applies the unified diffs using `patch -p1`
4. Verifies the patches were applied correctly

You can also apply patches manually:

```bash
cd $(python3 -c "import vibe; print(vibe.__path__[0])")/..
patch -p1 < patches/001-config-merge.patch
patch -p1 < patches/002-reasoning-unset.patch
```

## Compatibility

| Vibe version | Status |
|-------------|--------|
| v2.10.1 | Tested |
| v2.9.6 | Tested |
| v2.9.3 | Should work |
| Earlier | Untested |

## Related issues

- [#657](https://github.com/mistralai/mistral-vibe/issues/657) — Custom models in config.toml not respected
- [#585](https://github.com/mistralai/mistral-vibe/issues/585) — devstral-2 400 Bad Request
- [#617](https://github.com/mistralai/mistral-vibe/issues/617) — devstral-2 Invalid model: mistral-medium-3.5

## License

Apache 2.0 — see [LICENSE](LICENSE).
