# Browser Agent Architecture

## Design

- **Channel**: `channel="chrome"` (system Google Chrome). Falls back to bundled Chromium if Chrome is missing.
- **Profiles**: `~/.chrome-profiles/<sanitized_name>`. Ephemeral `temp`/`clean` uses a temp directory. CLI default profile is `temp`; avoid explicit `--profile default`.
- **Snapshot**: DOM query of visible interactive elements + `auth_state` heuristic — not Playwright accessibility.snapshot().
- **Locators**: `act` supports CSS, role+name, text, and label via Playwright locator API.
- **Locks**: Singleton lock files are removed only when no live `chrome.exe` process references the profile path.

## Anti-detection (minimal)

- `--disable-blink-features=AutomationControlled`
- `ja-JP` locale, `Asia/Tokyo` timezone
- Headed mode default for persistent profiles (SSO compatibility)

## Output contract

All commands emit JSON to **stdout only** (agents should parse stdout, not merged stderr).

## Capture storage

| Setting | Value |
| :--- | :--- |
| Default base | `~/.browser-agent/captures/` |
| Override | `BROWSER_AGENT_CAPTURE_DIR` env or `--output-dir` |
| Daily layout | `YYYY-MM-DD/HHMMSS-{host}--{route}.png` or `.webm` (same folder; type from extension) |
| Multi-device | opt-in `--all-devices` or `--devices mobile,tablet,desktop`; inserts `{device}-` after timestamp |
| Record scroll | `--scroll-mode smooth` (default) or `step` (linear viewport scroll + pause); JSON includes `scroll_mode`, `scroll_duration_ms`, `scroll_steps_performed` |
| Route slug | path segments + hash fragment + short query; `--` separates host from route |
| JSON fields | `screenshot_path` / `video_path`, `capture_dir`, `capture_default`, `captures_base`, `capture_route_slug`; multi → `captures[]` |

Omit `--output` for managed defaults; pass `--output` for one-off paths (relative paths resolve from cwd unless `--output-dir` is set).

## Intentionally simple (no over-engineering)

- **Session reuse**: `batch` command (single launch, multiple URLs) or `--cdp-url` / `BROWSER_AGENT_CDP_URL` to attach to running Chrome — not a background daemon.
- **Shadow DOM**: use explicit `shadow_host` + `selector`; no magic pierce flags.
- **Post-nav pause**: 250ms after `goto` (not a fixed 1s blanket sleep).
- **Auth detection**: lightweight regex heuristic — not a login detector service; never gate automation on `auth_state` alone.
- **Closed shadow roots**: unsupported; would need page-specific JS, not generic automation.
- **`act` post-snapshot**: always returns `current_page` after actions so agents can decide next step without a second `inspect` call; no `--no-snapshot` flag by design.
- **Screenshot prep**: `--spa-ready` or **`--full-page` (auto)** — full-document prefetch + lazy-image prime (`screenshot_prep` / `record_prep` in JSON).

## Maturity (2026-08-29)

**Status:** daily-use skill for dev/LP capture + post-login checks (**~88/100** adversarial).

| Proven | Not proven / out of scope |
| :--- | :--- |
| 108 automated smoke checks (`just test`) | Unattended SSO / bot bypass |
| `batch` session reuse + SSO matrix smoke | Closed shadow DOM |
| optional CDP attach (`--cdp-url`) | Cloudflare without manual dash login |
| localhost dev screenshot + act | Session daemon / always-on service |
| slush.app full-page SS + step video (lazy prime) | |
| GSC inspect+screenshot on real `work` profile | |
| JSON CLI contract, Windows `--actions-file` | |
| Capture dir + route slug + multi-device opt-in | |
| Record `--full-page` shares lazy prep with screenshot | |

**Do not add:** perf warning engine, magic shadow pierce, `--no-snapshot`, background session daemon.
