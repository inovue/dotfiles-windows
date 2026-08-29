---
name: browser-agent
description: >-
  Real Chrome browser automation with persistent profiles for dev capture and
  human-setup SSO sessions. Snapshots, role/text locators, screenshots, scroll video.
  Use temp for localhost; work/personal after setup_profile for dashboards.
  Not for unattended login. Prefer --actions-file on Windows.
---

# Browser Agent

Real Chrome + Playwright persistent profiles. Runner (after `just sync-rules`):

`$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py`

Repo SSOT: `configs/agents/skills/browser-agent/scripts/browser_runner.py`

**Quick start (localhost capture):**

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot `
  --url "localhost:5173" --profile temp --headless --full-page
```

---

## 1. When to Use What

| Task | Tool |
| :--- | :--- |
| SSO / saved cookies (GSC, Cloudflare, AWS) | **browser-agent** with `work` / `personal` profile |
| Local dev server screenshot / scroll video | **browser-agent** `--profile temp` |
| Quick in-session click/type without profiles | `cursor-ide-browser` MCP |

---

## 2. Profiles & headless (important)

| Profile | Default mode | Use for |
| :--- | :--- | :--- |
| `temp` / `clean` | headless | localhost, stateless capture, CI smoke |
| `work` / `personal` | **headed** | SSO dashboards after `setup_profile.ps1` |
| custom sanitized name | headed | long-lived login you name explicitly |

**Avoid `--profile default`** — runner **rejects** it with `recommended_profile: temp`. Use `work`, `personal`, or `temp` explicitly.

Override mode: `--headless` or `--headed`.

---

## 3. One-Time Login (persistent profile)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\setup_profile.ps1" -ProfileName "work"
```

Log in manually, close Chrome. Cookies persist under `~/.chrome-profiles/work`.

---

## 4. Commands

### inspect — page snapshot + auth hint

Returns `auth_state`: `likely_login_or_challenge` | `likely_authenticated` | `unknown`.

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" inspect --url "https://one.dash.cloudflare.com/" --profile work
```

### act — multi-step actions (**use --actions-file on Windows**)

Action fields (pick one locator style per step):

- `selector` — CSS
- `role` + `name` — Playwright get_by_role
- `text` — get_by_text
- `label` — get_by_label

Supported types: `click`, `fill`, `press`, `hover`, `select_option`, `wait_for_selector`, `wait_for_load`, `wait_for_network_idle`, `wait_for_timeout`, `wait_for_function` (`"expression": "document.querySelector('.ready')"`), `scroll_by`, `goto`, `new_tab`, `switch_tab`, `close_tab`, `extract_text`, `screenshot`.

Optional per-step: `"frame": "iframe#content"` for iframe-scoped locators.

**Locator priority:** prefer `role`+`name` or `text` over `inspect` snapshot selectors (snapshots often emit weak tags like `button`).

Viewport presets: `--device mobile|tablet|desktop` (overrides `--viewport`).

Shadow DOM: `"shadow_host": "#host", "selector": "#inner-btn"`. SPA hydration: `--wait-until networkidle`.

Network debug: `--network-output trace.json` (request/response log) or `--network-output trace.har`. JSON capture attaches to **all tabs** in the session; HAR is Playwright-managed on the context.

```powershell
@'
[{"type":"wait_for_network_idle","timeout":15000},{"type":"click","role":"button","name":"Save"}]
'@ | Set-Content -Encoding utf8NoBOM "$env:TEMP\ba-actions.json"

python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" act `
  --url "https://example.com" --profile temp --headless `
  --actions-file "$env:TEMP\ba-actions.json"
```

### screenshot — dev server or production page

**Default save location** (omit `--output`): `~/.browser-agent/captures/YYYY-MM-DD/HHMMSS-{host}--{route}.png`

Route slug includes path, hash (`#/…`), and a short query suffix. Host and route are separated by `--` (e.g. `localhost-5173--dashboard-settings.png`, `example-com--docs-api-v1.png`).

Override base directory: `--output-dir D:\captures` or env `BROWSER_AGENT_CAPTURE_DIR`. JSON includes `screenshot_path`, `capture_dir`, `capture_default`, `captures_base`.

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot `
  --url "localhost:5173" --profile temp --headless --full-page
```

Explicit path still works:

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot `
  --url "localhost:5173" --profile temp --headless `
  --output ".\capture.png" --full-page
```

**SPA / animation / lazy-load** — `--full-page` **automatically** enables SPA prep (lazy prefetch + image prime). Override with `--no-spa-ready`. Explicit `--spa-ready` still works on viewport-only shots.

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot `
  --url "localhost:5173/dashboard" --profile temp --headless `
  --spa-ready --full-page `
  --wait-for-function "document.querySelector('[data-ready]') !== null" `
  --output ".\capture.png"
```

Optional flags: `--settle-ms 800`, `--disable-animations`, `--prefetch-scroll`, `--wait-for-selector "#app"`.

**Responsive capture** (opt-in, 3× session time):

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot `
  --url "localhost:5173/dashboard" --profile temp --headless --all-devices --spa-ready --full-page
```

Or subset: `--devices mobile,desktop`. Multi-device filenames include the preset: `HHMMSS-mobile-localhost-5173--dashboard.png`. JSON returns `multi_device: true` and a `captures` array.

JSON output includes `screenshot_prep` (what ran before capture).

**Session follow-up:** read `screenshot_path` from JSON stdout with the Read tool.

### record — scroll video (.webm)

Defaults to **headed** for reliable video capture.

**Scroll modes** (`--scroll-mode`):

| Mode | Behavior |
| :--- | :--- |
| `smooth` (default) | Equal pixel steps at fixed interval (`--scroll-steps`, `--scroll-delay`) |
| `step` | Linear viewport scroll (default **2.2s**) then **3s pause** (`--scroll-duration-ms`, `--scroll-pause-ms`) |

With `--full-page --scroll-mode step`, scrolls viewport-by-viewport until the document bottom (safety cap 100 screens). **`--full-page` auto-runs SPA prep** (same lazy prefetch as screenshot) before scrolling. Without `--full-page`, `--scroll-steps` sets how many viewport jumps.

**Default save location** (omit `--output`): `~/.browser-agent/captures/YYYY-MM-DD/HHMMSS-{host}--{route}.webm` (same route slug rules as screenshot).

```powershell
# Smooth continuous scroll
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" record `
  --url "localhost:3000" --profile temp `
  --full-page --scroll-steps 10 --scroll-delay 500

# Viewport pause style (linear viewport scroll + 3s hold per screen)
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" record `
  --url "localhost:3000" --profile temp `
  --scroll-mode step --full-page
```

Explicit path:

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" record `
  --url "localhost:3000" --profile temp `
  --output ".\scroll-demo.webm" --full-page --scroll-steps 10 --scroll-delay 500
```

Responsive: `--all-devices` or `--devices mobile,tablet,desktop` (same JSON `captures` array as screenshot).

### eval — page-context JavaScript

Prefer `--script-file` on Windows.

```powershell
@'() => document.title'@ | Set-Content -Encoding utf8NoBOM "$env:TEMP\ba-script.js"
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" eval `
  --url "https://example.com" --profile temp --headless `
  --script-file "$env:TEMP\ba-script.js"
```

### cookies — export / import

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" cookies `
  --url "https://example.com" --profile work --export ".\cookies.json"
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" cookies `
  --url "https://example.com" --profile work --import ".\cookies.json"
```

Import JSON includes `verified_names` after reload in the same session.

### batch — multiple steps, one browser session (session reuse)

Runs `inspect`, `screenshot`, or `eval` steps without relaunching Chrome between URLs. JSON returns `session_reused: true`, `results[]`, and `session_mode: single_launch`.

```powershell
@'
[
  {"name":"GSC","command":"inspect","url":"https://search.google.com/search-console"},
  {"name":"GSC","command":"screenshot","url":"https://search.google.com/search-console","output":"$env:TEMP\\gsc.png"}
]
'@ | Set-Content -Encoding utf8NoBOM "$env:TEMP\sso-batch.json"

python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" batch `
  --batch-file "$env:TEMP\sso-batch.json" --profile work
```

SSO matrix smoke (optional): `just test-browser-sso-run` — uses batch + writes `tests/.tmp/browser-agent/sso-matrix-report.json` with `auth_assertion` per target (`warn_login` ≠ logged in).

**Not supported in batch:** `act`, `record`, `cookies`, multi-device. Use separate invocations or extend with `act` after a single `inspect`.

### CDP attach — reuse a running Chrome (cross-invocation)

Skip cold start by attaching to Chrome already running with remote debugging:

```powershell
& "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" `
  --remote-debugging-port=9222 `
  --user-data-dir="$env:USERPROFILE\.chrome-profiles\work"

$env:BROWSER_AGENT_CDP_URL = "http://127.0.0.1:9222"
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" batch `
  --batch-file "$env:TEMP\sso-batch.json" --profile work --cdp-url $env:BROWSER_AGENT_CDP_URL
```

CDP mode skips profile lock acquisition and disconnects without closing your Chrome window. JSON may include `cdp_profile_warning` when the running Chrome `--user-data-dir` does not match `--profile`. Works with any command that accepts `--cdp-url`.

---

## 5. Performance budget (typical cold start)

| Command | Target | Notes |
| :--- | :--- | :--- |
| inspect | ≤ 15s | JSON includes `elapsed_ms` (agent judges; runner does not warn) |
| screenshot | ≤ 20s | add `--spa-ready` for SPAs; `--wait-until networkidle` also helps |
| act | ≤ 30s | prefer role/text locators over long waits |
| batch (2–4 SSO targets) | ≤ 35s | one launch; use `--cdp-url` to skip relaunch across invocations |
| record | ≤ 25s | headed; `--headless` auto-fallback if needed |
| `--wait-until networkidle` | +5–15s | SPA dashboards only |

---

## 6. Recovery Runbook

1. **`auth_state: likely_login_or_challenge`** — re-run `setup_profile.ps1`, or retry headed without `--headless`.
2. **`profile_lock_warning`** — close Chrome windows using that profile, retry.
3. **`setup_profile.ps1` vs runner** — do not leave manual Chrome open on the same profile; close it before running the runner.
4. **SPA not ready** — add `wait_for_network_idle` or `wait_for_selector` before clicks.
5. **Windows JSON errors** — never inline JSON in PowerShell; always `--actions-file`.
6. **Skill path missing** — run `just sync-rules` from dotfiles repo.
7. **Captures disk growth** — prune day folders older than 30 days:

```powershell
Get-ChildItem "$env:USERPROFILE\.browser-agent\captures" -Directory |
  Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
  Remove-Item -Recurse -Force
```

---

## 7. Limits (honest)

- Snapshot walks light DOM + **open** shadow roots only; closed (`mode: "closed"`) shadow trees are invisible to inspect/act.
- Interactive element list capped at ~90 (`interactive_truncated: true` when cap hit); prefer role/text locators.
- inspect reports `shadow_interactive_count` for shadow-only controls.
- Tab actions: `new_tab`, `switch_tab` (index), `close_tab` — one browser context, no parallel profiles.
- Cross-origin iframes are not supported by `"frame"` locators; same-origin or `srcdoc` only.
- No parallel runs on the same profile (`.browser-agent.lock`).
- `cookies --import` verifies names in the **same session** only; a new invocation starts a fresh browser context.
- `cookies --export` writes session tokens to disk — never commit; add path to `.gitignore`.
- `eval` runs arbitrary page JavaScript — use only on trusted URLs.
- Video recording may require headed mode on some hosts.
- Bot challenges need human-in-the-loop via `setup_profile.ps1`.

---

## 8. Minimal SSO check (after setup_profile)

`auth_state` is a **heuristic hint only** — confirm with screenshot or manual glance before relying on it.

**Known false signals (do not treat as ground truth):**

| Signal | Can mislead when |
| :--- | :--- |
| `likely_authenticated` | Page title contains "console" / "dashboard" on a login screen |
| `likely_login_or_challenge` | Logged-in page mentions "sign out" or OAuth in footer text |
| `unknown` | Authenticated app with minimal body text |

SSO matrix `auth_assertion: warn_login` means **captured ≠ logged in** — review the screenshot.

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" inspect `
  --url "https://search.google.com/search-console" --profile work

python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot `
  --url "https://search.google.com/search-console" --profile work `
  --output "$env:TEMP\gsc-check.png"
```

Use inspect output as a triage hint. Read `gsc-check.png` in the agent session (or visually) before proceeding. Re-run `setup_profile.ps1` headed if you still see a login or challenge screen.

### Cloudflare Access check (same rules)

```powershell
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" inspect `
  --url "https://one.dash.cloudflare.com/" --profile work

python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot `
  --url "https://one.dash.cloudflare.com/" --profile work `
  --output "$env:TEMP\cf-check.png"
```

Bot challenges cannot be automated — complete them once via `setup_profile.ps1`, then verify with screenshot.

---

## 9. Manual SSO smoke (optional, local)

After logging into `work` via `setup_profile.ps1`:

```powershell
just test-browser-sso-run
```

Or set `$env:BROWSER_AGENT_SSO_TEST = '1'` then `just test-browser-sso`. Skipped in normal `just test` / CI. Requires `~/.chrome-profiles/work` and network access.

**Expected local results (2026-08):** GSC often `likely_authenticated` when logged in via `setup_profile`. Cloudflare Dashboard may stay `likely_login_or_challenge` until you log into `one.dash.cloudflare.com` in the same Chrome profile — not automatic from GSC login alone.

---

## 10. Agent JSON contract (escalation)

Every command stdout is JSON. Before continuing automation, check:

| Signal | Meaning | Agent must |
| :--- | :--- | :--- |
| `user_action_required: true` | Human step needed | Stop unattended clicks; tell the user what blocked progress |
| `recommended_actions[]` | Ordered recovery hints | Follow top item or ask the user to choose |
| `auth_state: likely_login_or_challenge` | Login / CAPTCHA / SSO | Run `setup_profile.ps1`, verify with screenshot, do not brute-force |
| `batch` + step `auth_state: likely_login_or_challenge` | Same, inside `results[]` | Sets top-level `user_action_required`; review that step's screenshot |
| `interactive_truncated: true` | inspect hit 90-element cap | Do not trust snapshot selectors; use role/text |
| `cdp_profile_warning` | CDP Chrome wrong profile dir | Fix `--user-data-dir` or `--profile` mismatch |
| `status: partial_failure` | One or more actions failed | Read `current_page` + `action_results`; ask user for locator |
| `capture_incomplete: true` | Lazy images may be missing in PNG/webm | Review file visually; check `images_pending_after_prime` |
| `batch.failed_step_count > 0` | Some steps failed | Do not treat batch as full success |
| `batch.login_challenge_steps[]` | Login-like steps in batch | Review those screenshots before automation |
| `status: error` + profile lock message | Chrome holds the profile | Close Chrome for that profile; retry |
| `session_hint` | Follow-up for the agent | Prefer reading `screenshot_path` over guessing page state |
| `sensitive_export: true` | Cookies JSON on disk | Never commit; treat `export_path` as secrets |

Do **not** ignore `user_action_required` and retry the same action loop.
