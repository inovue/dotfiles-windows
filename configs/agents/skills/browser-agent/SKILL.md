---
name: browser-agent
description: >-
  Ultra-reliable, high-speed browser automation skill using real Google Chrome with persistent profiles,
  headless/headed modes, and anti-bot stealth. Use whenever you need to interact with logged-in services
  (Cloudflare Access, Google Search Console, GitHub, AWS, internal portals), scrape dynamic SPAs, fill forms,
  or perform web research.
---

# Browser Agent Workflows & Robust Execution Engine

This skill equips agents with a production-grade, highly resilient browser automation engine powered by **real Google Chrome**, **Accessibility Tree (a11y) snapshots**, and **isolated persistent profiles**.

---

## 1. Core Principles for 99.9% Reliability

1. **Deterministic Execution + Semantic Locators**:
   - Do NOT guess raw CSS class names.
   - Use Accessibility Tree snapshots or ARIA roles (role=button, text matching) to guarantee UI-resilience.
2. **Session Persistence Without Process Lock**:
   - Use dedicated named profiles in ~/.chrome-profiles/<profile_name>.
   - Never share profiles across concurrent processes.
3. **Anti-Bot & Real-Chrome First**:
   - Always run with channel="chrome" and automation flags masked to bypass Cloudflare Turnstile, Datadome, and Google unsecure browser warnings.

---

## 2. Profile Management & Mode Rules

| Profile | Typical Target / Use Case | Default Mode | Directory Location |
| :--- | :--- | :--- | :--- |
| work | Cloudflare Zero Trust, AWS, Jira, internal SSO dashboards | --headless | ~/.chrome-profiles/work |
| personal | Google Search Console, GitHub, Gmail, personal portals | --headless | ~/.chrome-profiles/personal |
| temp / clean | Fresh, isolated session without cookies or cache | --headless | Auto-generated temporary directory |
| <custom> | Any project-specific task (e.g. gsc-client-a) | As requested | ~/.chrome-profiles/<custom> |

---

## 3. Practical Agent Recipes & Command Patterns

The runner script is located at:
`~/.gemini/config/skills/browser-agent/scripts/browser_runner.py` (or within this workspace under `.agents/skills/browser-agent/scripts/browser_runner.py`)

### Recipe 1: Inspect Page & Extract a11y Snapshot (Ultra-Fast)
Inspect any dynamic webpage, outputting page title, clean text, and interactive elements with low token overhead.

```powershell
python "$env:USERPROFILE\.gemini\config\skills\browser-agent\scripts\browser_runner.py" inspect --url "https://news.ycombinator.com" --profile temp --headless
```

### Recipe 2: Run Authenticated Task with Persistent Profile
Access a protected dashboard (e.g. Cloudflare Access or GSC) using a logged-in profile:

```powershell
python "$env:USERPROFILE\.gemini\config\skills\browser-agent\scripts\browser_runner.py" inspect --url "https://one.dash.cloudflare.com/" --profile work --headless
```

### Recipe 3: Multi-Step Actions (Click, Fill, Wait, Extract)
Execute a sequence of deterministic actions and extract structured results:

```powershell
python "$env:USERPROFILE\.gemini\config\skills\browser-agent\scripts\browser_runner.py" act --url "https://github.com/login" --profile temp --actions '[{"type":"fill","selector":"input#login_field","value":"testuser"},{"type":"fill","selector":"input#password","value":"testpass"},{"type":"click","selector":"input[type=\"submit\"]"},{"type":"wait_for_load","state":"domcontentloaded"}]' --headless
```

### Recipe 4: Evaluate JavaScript / Extract Data Object
Run custom JS directly inside the page context and receive JSON stdout:

```powershell
python "$env:USERPROFILE\.gemini\config\skills\browser-agent\scripts\browser_runner.py" eval --url "https://example.com" --script "() => ({ heading: document.querySelector('h1').innerText, links: Array.from(document.querySelectorAll('a')).map(a => a.href) })" --profile temp --headless
```

### Recipe 5: Setup or Login to a New Profile (One-Time Human Step)
Open a visible Chrome window to log into 2FA/Google/SSO and persist credentials:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.gemini\config\skills\browser-agent\scripts\setup_profile.ps1" -ProfileName "work"
```

### Recipe 6: Capture Screenshot
Capture a high-fidelity screenshot of any page (viewport or full-page):

```powershell
python "$env:USERPROFILE\.gemini\config\skills\browser-agent\scripts\browser_runner.py" screenshot --url "https://google.com" --output "screenshot.png" --profile temp --headless
```

---

## 4. Error Handling & Recovery Runbook

1. **Singleton Lock Detected**:
   - If a previous Chrome crash left a lock file, `browser_runner.py` automatically detects and clears stale SingletonLock files.
2. **Cloudflare / Bot Challenge Encountered**:
   - Run without --headless (visible mode) and prompt the user to resolve any interactive challenge, or use setup_profile.ps1 to solve it once in the persistent profile.
3. **Dynamic SPA Loading Delays**:
   - Pass {"type": "wait_for_selector", "selector": "your-target-element", "timeout": 15000} in action sequences.