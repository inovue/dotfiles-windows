import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

try:
    from playwright.async_api import (
        async_playwright,
        BrowserContext,
        Locator,
        Page,
        TimeoutError as PlaywrightTimeoutError,
    )
except ImportError:
    print(json.dumps({
        "status": "error",
        "message": "Playwright is not installed. Run: pip install playwright (Google Chrome must also be installed for channel=chrome)",
    }))
    sys.exit(1)

DEVICE_PRESETS: Dict[str, Dict[str, int]] = {
    "desktop": {"width": 1280, "height": 800},
    "mobile": {"width": 390, "height": 844},
    "tablet": {"width": 834, "height": 1194},
}
PROFILES_BASE = Path.home() / ".chrome-profiles"
CAPTURES_BASE = Path.home() / ".browser-agent" / "captures"
CAPTURES_ENV = "BROWSER_AGENT_CAPTURE_DIR"
CDP_URL_ENV = "BROWSER_AGENT_CDP_URL"
PROFILE_LOCK_NAME = ".browser-agent.lock"
PROFILE_LOCK_TTL_SEC = 7200
WAIT_UNTIL_CHOICES = ("domcontentloaded", "load", "networkidle")
SCROLL_MODES = ("smooth", "step")
STEP_SCROLL_DURATION_MS_DEFAULT = 2200
STEP_SCROLL_PAUSE_MS_DEFAULT = 3000
NETWORK_LOG_CAP = 200
LOCK_NAMES = ["SingletonLock", "SingletonCookie", "SingletonSocket", "lockfile"]
LOGIN_HINTS = re.compile(
    r"sign[\s-]?in|log[\s-]?in|authenticate|oauth|sso|accounts\.google|"
    r"cloudflareaccess|challenge|verify it.s you|two-factor|2fa|passkey",
    re.I,
)


def sanitize_profile_name(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_-]", "_", name)


def validate_profile_name(profile: str) -> Optional[str]:
    if profile == "default":
        return (
            "Profile 'default' is a legacy footgun. "
            "Use temp (headless capture), work, personal, or a custom sanitized name."
        )
    return None


def apply_capture_prep_flags(output: Dict[str, Any], prep_meta: Dict[str, Any]) -> None:
    pending = prep_meta.get("images_pending_after_prime")
    if isinstance(pending, int) and pending > 0:
        output["capture_incomplete"] = True
        output["images_pending_after_prime"] = pending


def resolve_headless(profile: str, headless_flag: bool, headed_flag: bool) -> bool:
    if headless_flag and headed_flag:
        raise ValueError("Use only one of --headless or --headed")
    if headless_flag:
        return True
    if headed_flag:
        return False
    return profile in ("temp", "clean")


def _profile_in_use(profile_dir: Path) -> bool:
    needle = str(profile_dir.resolve()).lower()
    try:
        if sys.platform == "win32":
            ps = (
                "Get-CimInstance Win32_Process -Filter \"name='chrome.exe'\" "
                "| Select-Object -ExpandProperty CommandLine"
            )
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps],
                capture_output=True,
                text=True,
                timeout=15,
            )
            return needle in result.stdout.lower()
        result = subprocess.run(
            ["pgrep", "-af", "chrome"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return needle in result.stdout.lower()
    except Exception:
        return (profile_dir / "SingletonLock").exists()


def cleanup_singleton_locks(profile_dir: Path) -> Optional[str]:
    if _profile_in_use(profile_dir):
        return f"Profile '{profile_dir.name}' appears in use; skipped lock cleanup"
    for lock_name in LOCK_NAMES:
        lock_file = profile_dir / lock_name
        if not lock_file.exists():
            continue
        try:
            if lock_file.is_dir() or lock_file.is_symlink():
                lock_file.unlink()
            else:
                lock_file.unlink(missing_ok=True)
        except Exception:
            pass
    return None


def acquire_profile_lock(profile_dir: Path) -> Tuple[Optional[Path], Optional[str]]:
    lock_path = profile_dir / PROFILE_LOCK_NAME
    if lock_path.exists():
        _clear_stale_profile_lock(lock_path)
    try:
        fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(str(os.getpid()))
        return lock_path, None
    except FileExistsError:
        try:
            holder = lock_path.read_text(encoding="utf-8").strip()
        except Exception:
            holder = "unknown"
        return None, (
            f"Profile '{profile_dir.name}' is locked (pid {holder}). "
            "Close the other browser-agent session or remove the stale lock file."
        )


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        if sys.platform == "win32":
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", f"Get-Process -Id {pid} -ErrorAction SilentlyContinue"],
                capture_output=True,
                timeout=10,
            )
            return result.returncode == 0
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError, subprocess.SubprocessError):
        return False


def _clear_stale_profile_lock(lock_path: Path) -> bool:
    try:
        holder = int(lock_path.read_text(encoding="utf-8").strip())
    except (ValueError, OSError):
        holder = -1
    age = time.time() - lock_path.stat().st_mtime
    if _pid_alive(holder) and age <= PROFILE_LOCK_TTL_SEC:
        return False
    try:
        lock_path.unlink()
        return True
    except OSError:
        return False


def attach_network_listeners(page: Page, sink: List[Dict[str, Any]]) -> None:
    def on_request(req) -> None:
        if len(sink) >= NETWORK_LOG_CAP:
            return
        sink.append({"kind": "request", "url": req.url, "method": req.method, "resource_type": req.resource_type})

    def on_response(resp) -> None:
        if len(sink) >= NETWORK_LOG_CAP:
            return
        sink.append({"kind": "response", "url": resp.url, "status": resp.status})

    page.on("request", on_request)
    page.on("response", on_response)


def attach_network_listeners_context(context: BrowserContext, sink: List[Dict[str, Any]]) -> None:
    def on_page(page: Page) -> None:
        attach_network_listeners(page, sink)

    context.on("page", on_page)
    for page in context.pages:
        attach_network_listeners(page, sink)


def release_profile_lock(lock_path: Optional[Path]) -> None:
    if lock_path and lock_path.exists():
        try:
            lock_path.unlink()
        except Exception:
            pass


def load_actions(actions: Optional[str], actions_file: Optional[str]) -> List[Dict[str, Any]]:
    if actions_file:
        raw = Path(actions_file).read_text(encoding="utf-8")
    elif actions:
        raw = actions
    else:
        raise ValueError("Provide --actions or --actions-file")
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError("Actions JSON must be an array")
    return data


def infer_auth_state(url: str, title: str, text_preview: str) -> str:
    blob = f"{url} {title} {text_preview}"
    if LOGIN_HINTS.search(blob):
        return "likely_login_or_challenge"
    lowered = blob.lower()
    if any(k in lowered for k in ("dashboard", "console", "welcome back")):
        return "likely_authenticated"
    if "search-console" in lowered and "sign" not in lowered:
        return "likely_authenticated"
    return "unknown"


def enrich_output_guidance(output: Dict[str, Any], args: argparse.Namespace) -> None:
    """Add user_action_required + recommended_actions without over-engineering."""
    actions: List[str] = []
    user_action = False
    status = output.get("status")
    auth = output.get("auth_state")
    profile = args.profile
    persistent = profile not in ("temp", "clean")

    if auth == "likely_login_or_challenge":
        user_action = True
        actions.append("Run setup_profile.ps1 headed, log in manually, then re-run inspect + screenshot.")
        actions.append("Do not continue automated clicks until screenshot confirms a logged-in view.")
    elif auth == "unknown" and persistent and args.command in ("inspect", "screenshot", "act"):
        actions.append("Capture or read a screenshot and confirm login state with the user before proceeding.")
    elif auth == "likely_authenticated" and persistent and args.command in ("inspect", "screenshot"):
        actions.append("Visually confirm screenshot_path before unattended automation on this profile.")

    if args.command == "batch":
        for step in output.get("results", []):
            step_auth = step.get("auth_state")
            if step_auth == "likely_login_or_challenge":
                user_action = True
                output["auth_state"] = "likely_login_or_challenge"
                actions.append(
                    f"Step {step.get('step')} ({step.get('name') or step.get('url')}): login/challenge detected; run setup_profile and verify screenshot."
                )
                break
            prep = step.get("screenshot_prep")
            if isinstance(prep, dict):
                pending = prep.get("images_pending_after_prime")
                if isinstance(pending, int) and pending > 0:
                    actions.append(
                        f"Step {step.get('step')} capture may be incomplete ({pending} images pending after prep)."
                    )

    if status == "partial_failure":
        user_action = True
        failed = next((r for r in output.get("action_results", []) if r.get("status") == "failed"), None)
        if not failed and args.command == "batch":
            failed = next((r for r in output.get("results", []) if r.get("status") != "success"), None)
        err = (failed or {}).get("error", "")
        actions.append("Inspect current_page snapshot; ask the user for the correct locator or manual step.")
        if args.command == "batch":
            actions[-1] = "Review batch results[] for failed steps; inspect auth_state and screenshots per target."
        if err:
            actions.append(f"Last action error: {err}")
    elif status == "error":
        err = str(output.get("error") or output.get("message") or "")
        if "lock" in err.lower() or output.get("profile_lock_warning"):
            user_action = True
            actions.append("Close Chrome windows using this profile, then retry.")
        elif output.get("error") == "Video file was not produced; retry with --headed":
            actions.append("Retry record with --headed (video capture often needs a visible browser).")
        elif "Timed out" in err:
            actions.append("Retry with --wait-until networkidle, add wait_for_selector, or ask the user if the page needs manual steps.")
        elif "connect_over_cdp" in err.lower() or "econnrefused" in err.lower():
            actions.append(
                "Ensure Chrome is running with --remote-debugging-port and the CDP URL is reachable, or omit --cdp-url to launch a profile."
            )

    for prep_key in ("screenshot_prep", "record_prep"):
        prep = output.get(prep_key)
        if isinstance(prep, dict):
            pending = prep.get("images_pending_after_prime")
            if isinstance(pending, int) and pending > 0:
                actions.append(
                    f"Capture may be incomplete ({pending} images still pending after prep); review output or retry with --wait-until networkidle."
                )

    if output.get("record_fallback"):
        actions.append("Headed fallback was used after headless record failed; prefer --headed for video on this host.")

    if output.get("cdp_profile_warning"):
        actions.append(output["cdp_profile_warning"])

    if output.get("interactive_truncated"):
        actions.append("inspect interactive list hit the 90-element cap; prefer role/text locators over snapshot selectors.")

    if output.get("sensitive_export"):
        actions.append("Cookies export contains session tokens; never commit the file; add path to .gitignore.")

    if output.get("capture_incomplete"):
        pending = output.get("images_pending_after_prime", "?")
        actions.append(
            f"Capture may be incomplete ({pending} images pending after prep); review visually before using the file."
        )
        if status == "success":
            output["session_hint"] = (
                "Capture saved as success but lazy images may still be loading; "
                "read screenshot_path and verify visually before shipping."
            )

    if args.command == "batch" and output.get("failed_step_count", 0) > 0:
        actions.append(
            f"Batch had {output['failed_step_count']} failed step(s) out of {output.get('step_count', '?')}; "
            "do not treat overall status as full success."
        )

    # Dedupe while preserving order
    seen: set[str] = set()
    unique = [a for a in actions if not (a in seen or seen.add(a))]

    if unique:
        output["recommended_actions"] = unique[:4]
    if user_action:
        output["user_action_required"] = True
        output.setdefault(
            "session_hint",
            "Stop unattended automation; share status with the user and wait for manual guidance or setup_profile.",
        )


def emit_json(
    output: Dict[str, Any],
    args: argparse.Namespace,
    profile_lock_path: Optional[Path] = None,
) -> None:
    """Write JSON to stdout only (diagnostics belong in JSON fields, not stderr)."""
    enrich_output_guidance(output, args)
    release_profile_lock(profile_lock_path)
    sys.stdout.write(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    sys.stdout.flush()


def load_script(script: Optional[str], script_file: Optional[str]) -> str:
    if script_file:
        return Path(script_file).read_text(encoding="utf-8")
    if script:
        return script
    raise ValueError("Provide --script or --script-file")


def resolve_root(page: Page, act: Dict[str, Any]):
    frame_sel = act.get("frame") or act.get("frame_selector")
    if frame_sel:
        return page.frame_locator(frame_sel)
    return page


def resolve_locator(page: Page, act: Dict[str, Any]) -> Locator:
    root = resolve_root(page, act)
    role = act.get("role")
    if role:
        kwargs: Dict[str, Any] = {"name": act.get("name") or act.get("text")}
        if act.get("exact"):
            kwargs["exact"] = True
        return root.get_by_role(role, **{k: v for k, v in kwargs.items() if v is not None})
    if act.get("text"):
        return root.get_by_text(act["text"], exact=bool(act.get("exact")))
    if act.get("label"):
        return root.get_by_label(act["label"], exact=bool(act.get("exact")))
    selector = act.get("selector")
    if not selector:
        raise ValueError("Action requires selector, role+name, text, or label")
    shadow_host = act.get("shadow_host")
    if shadow_host:
        return root.locator(shadow_host).locator(selector)
    return root.locator(selector)


async def extract_page_snapshot(page: Page) -> Dict[str, Any]:
    title = await page.title()
    url = page.url

    semantic_data = await page.evaluate(
        """() => {
        const interactiveSelectors = 'a, button, input, select, textarea, [role="button"], [role="link"], [role="checkbox"], [role="menuitem"], [role="tab"]';
        const results = [];
        const seen = new Set();
        function pushElement(el, inShadow) {
            if (seen.has(el)) return;
            if (results.length >= 90) return;
            seen.add(el);
            const rect = el.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0) return;
            const style = window.getComputedStyle(el);
            if (style.visibility === 'hidden' || style.display === 'none') return;
            const tag = el.tagName.toLowerCase();
            const role = el.getAttribute('role') || tag;
            const text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.getAttribute('value') || el.getAttribute('title') || '').trim();
            const name = el.getAttribute('name') || '';
            const type = el.getAttribute('type') || '';
            let selector = tag;
            if (el.id) selector = '#' + el.id;
            else if (name) selector = `${tag}[name="${name}"]`;
            else if (type) selector = `${tag}[type="${type}"]`;
            results.push({
                tag, role,
                text: text.slice(0, 120),
                selector,
                id: el.id || null,
                name: name || null,
                type: type || null,
                href: el.href || null,
                in_shadow: inShadow
            });
        }
        function walk(root, inShadow) {
            root.querySelectorAll(interactiveSelectors).forEach(el => pushElement(el, inShadow));
            root.querySelectorAll('*').forEach(node => {
                if (node.shadowRoot) walk(node.shadowRoot, true);
            });
        }
        walk(document, false);
        const bodyText = document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 3000) : '';
        const shadowCount = results.filter(r => r.in_shadow).length;
        return {
            elements: results,
            text_preview: bodyText.trim(),
            shadow_count: shadowCount,
            interactive_truncated: results.length >= 90,
        };
    }"""
    )

    text_preview = semantic_data.get("text_preview", "")
    return {
        "status": "success",
        "title": title,
        "url": url,
        "auth_state": infer_auth_state(url, title, text_preview),
        "interactive_count": len(semantic_data.get("elements", [])),
        "interactive_truncated": bool(semantic_data.get("interactive_truncated")),
        "shadow_interactive_count": semantic_data.get("shadow_count", 0),
        "interactive_elements": semantic_data.get("elements", []),
        "text_preview": text_preview,
    }


async def execute_actions(
    page: Page, context: BrowserContext, actions: List[Dict[str, Any]]
) -> Tuple[List[Dict[str, Any]], Page]:
    results: List[Dict[str, Any]] = []
    current = page
    passthrough = {
        "wait_for_load", "wait_for_timeout", "wait_for_network_idle", "scroll_by", "goto",
        "new_tab", "switch_tab", "close_tab",
    }
    for idx, act in enumerate(actions):
        act_type = act.get("type")
        timeout = act.get("timeout", 10000)
        step_res: Dict[str, Any] = {"step": idx + 1, "type": act_type, "status": "pending"}
        try:
            target = resolve_locator(current, act) if act_type not in passthrough else None

            if act_type == "click":
                await target.click(timeout=timeout)
            elif act_type == "fill":
                await target.fill(str(act.get("value", "")), timeout=timeout)
            elif act_type == "press":
                await target.press(act.get("key", "Enter"), timeout=timeout)
            elif act_type == "hover":
                await target.hover(timeout=timeout)
            elif act_type == "select_option":
                await target.select_option(act.get("value"), timeout=timeout)
            elif act_type == "wait_for_selector":
                root = resolve_root(current, act)
                if act.get("role"):
                    await root.get_by_role(act["role"], name=act.get("name")).wait_for(timeout=timeout)
                elif act.get("text"):
                    await root.get_by_text(act["text"]).wait_for(timeout=timeout)
                else:
                    await root.locator(act["selector"]).wait_for(timeout=timeout)
            elif act_type == "wait_for_function":
                expr = act.get("expression") or act.get("script")
                if not expr:
                    raise ValueError("wait_for_function requires expression or script")
                await current.wait_for_function(expr, timeout=timeout)
            elif act_type == "wait_for_load":
                await current.wait_for_load_state(act.get("state", "domcontentloaded"), timeout=timeout)
            elif act_type == "wait_for_network_idle":
                await current.wait_for_load_state("networkidle", timeout=timeout)
            elif act_type == "wait_for_timeout":
                await asyncio.sleep(act.get("milliseconds", 1000) / 1000.0)
            elif act_type == "scroll_by":
                delta = act.get("pixels", 600)
                await current.evaluate(f"window.scrollBy(0, {int(delta)})")
            elif act_type == "goto":
                wu = act.get("wait_until", "domcontentloaded")
                if wu not in WAIT_UNTIL_CHOICES:
                    wu = "domcontentloaded"
                await goto_with_retry(current, normalize_url(act["url"]), timeout, act.get("retries", 1), wu)
            elif act_type == "new_tab":
                current = await context.new_page()
                if act.get("url"):
                    wu = act.get("wait_until", "domcontentloaded")
                    if wu not in WAIT_UNTIL_CHOICES:
                        wu = "domcontentloaded"
                    retries = act.get("retries", 1)
                    await goto_with_retry(
                        current, normalize_url(act["url"]), timeout, retries, wu
                    )
                step_res["tab_index"] = context.pages.index(current)
                step_res["url"] = current.url
            elif act_type == "switch_tab":
                tab_idx = int(act.get("index", act.get("value", 0)))
                if tab_idx < 0 or tab_idx >= len(context.pages):
                    raise ValueError(f"Tab index out of range: {tab_idx}")
                current = context.pages[tab_idx]
                await current.bring_to_front()
                step_res["tab_index"] = tab_idx
                step_res["url"] = current.url
            elif act_type == "close_tab":
                if len(context.pages) <= 1:
                    raise ValueError("Cannot close the last tab")
                await current.close()
                current = context.pages[-1]
                await current.bring_to_front()
                step_res["tab_index"] = context.pages.index(current)
                step_res["url"] = current.url
            elif act_type == "extract_text":
                step_res["data"] = await target.inner_text(timeout=timeout)
            elif act_type == "screenshot":
                out_path, used_default = resolve_output_path(
                    act.get("path") or act.get("output"),
                    url=current.url,
                    ext=".png",
                    output_dir=act.get("output_dir"),
                )
                prep_meta = await prepare_page_capture(
                    current,
                    {
                        "spa_ready": act.get("spa_ready"),
                        "settle_ms": act.get("settle_ms", 0),
                        "disable_animations": act.get("disable_animations"),
                        "prefetch_scroll": act.get("prefetch_scroll"),
                        "full_page": act.get("full_page"),
                        "wait_for_selector": act.get("wait_for_selector") or act.get("selector"),
                        "wait_for_function": act.get("wait_for_function") or act.get("expression"),
                        "wait_until": act.get("wait_until"),
                    },
                    timeout,
                )
                await current.screenshot(path=str(out_path), full_page=bool(act.get("full_page")))
                step_res["path"] = str(out_path)
                step_res["capture_dir"] = str(out_path.parent)
                step_res["capture_default"] = used_default
                step_res["capture_route_slug"] = slug_from_url(current.url)
                step_res["screenshot_prep"] = prep_meta
            else:
                step_res["status"] = "error"
                step_res["error"] = f"Unknown action type: {act_type}"
                results.append(step_res)
                break

            if step_res["status"] != "error":
                step_res["status"] = "success"
        except Exception as e:
            step_res["status"] = "failed"
            step_res["error"] = str(e)
            results.append(step_res)
            break
        results.append(step_res)
    return results, current


def normalize_url(url: str) -> str:
    url = url.strip()
    if url.startswith(("http://", "https://", "file://", "data:", "about:")):
        return url
    if url.startswith(("localhost", "127.0.0.1", "0.0.0.0", "::1")):
        return f"http://{url}"
    return f"https://{url}"


def resolve_capture_dir(output_dir: Optional[str] = None) -> Path:
    raw = output_dir or os.environ.get(CAPTURES_ENV)
    base = Path(raw).expanduser().resolve() if raw else CAPTURES_BASE.resolve()
    base.mkdir(parents=True, exist_ok=True)
    return base


def _sanitize_slug_part(text: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "-", text.lower()).strip("-")
    return re.sub(r"-+", "-", cleaned)


def slug_from_url(url: str) -> str:
    """Filesystem-safe slug: host + route (path, hash fragment, short query)."""
    parsed = urlparse(normalize_url(url))
    scheme = (parsed.scheme or "").lower()
    host_slug = _sanitize_slug_part(parsed.netloc.replace(".", "-") if parsed.netloc else "")

    route_segments: List[str] = []
    path = (parsed.path or "").strip("/")
    if path:
        route_segments.extend(path.split("/"))
    fragment = (parsed.fragment or "").strip("/")
    if fragment:
        route_segments.extend(fragment.split("/"))
    if parsed.query:
        query_slug = _sanitize_slug_part(parsed.query)
        if query_slug:
            route_segments.append(query_slug[:32])

    route_parts = [_sanitize_slug_part(seg) for seg in route_segments if seg]
    route_parts = [part for part in route_parts if part]
    route_slug = "-".join(route_parts)

    if not host_slug:
        if scheme in ("http", "https"):
            host_slug = "page"
        elif scheme:
            host_slug = _sanitize_slug_part(f"{scheme}-{parsed.path or 'page'}")
        else:
            host_slug = "page"

    slug = f"{host_slug}--{route_slug}" if route_slug else host_slug
    if len(slug) > 100:
        if route_slug:
            keep = max(20, 100 - len(host_slug) - 2)
            slug = f"{host_slug}--{route_slug[:keep].rstrip('-')}"
        else:
            slug = slug[:100].rstrip("-")
    return slug or "page"


def default_capture_path(
    url: str, ext: str, output_dir: Optional[str] = None, device: Optional[str] = None
) -> Path:
    now = datetime.now()
    day_dir = resolve_capture_dir(output_dir) / now.strftime("%Y-%m-%d")
    day_dir.mkdir(parents=True, exist_ok=True)
    device_prefix = f"{device}-" if device else ""
    filename = f"{now.strftime('%H%M%S')}-{device_prefix}{slug_from_url(url)}{ext}"
    return day_dir / filename


def resolve_output_path(
    output: Optional[str],
    *,
    url: str,
    ext: str,
    output_dir: Optional[str] = None,
    device: Optional[str] = None,
) -> Tuple[Path, bool]:
    if output:
        path = Path(output).expanduser()
        if not path.is_absolute() and output_dir:
            path = resolve_capture_dir(output_dir) / path
        if device:
            path = path.with_name(f"{path.stem}-{device}{path.suffix}")
        path = path.resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        return path, False
    path = default_capture_path(url, ext, output_dir, device=device)
    return path, True


ALL_DEVICE_PRESETS: Tuple[str, ...] = ("mobile", "tablet", "desktop")


def resolve_capture_device_plan(args: argparse.Namespace) -> Tuple[List[Optional[str]], bool]:
    if args.command not in ("screenshot", "record"):
        return [None], False

    all_devices = bool(getattr(args, "all_devices", False))
    devices_raw = getattr(args, "devices", None)
    single_device = getattr(args, "device", None)

    if all_devices:
        if devices_raw or single_device:
            raise ValueError("Use only one of --all-devices, --devices, or --device")
        return list(ALL_DEVICE_PRESETS), True

    if devices_raw:
        if single_device:
            raise ValueError("Use either --device or --devices, not both")
        names = [part.strip().lower() for part in devices_raw.split(",") if part.strip()]
        if not names:
            raise ValueError("--devices must list at least one preset")
        unknown = [name for name in names if name not in DEVICE_PRESETS]
        if unknown:
            raise ValueError(f"Unknown device preset(s): {', '.join(unknown)}")
        return names, len(names) > 1

    if single_device:
        return [single_device], False

    return [None], False


def merge_multi_device_captures(results: List[Dict[str, Any]], command: str) -> Dict[str, Any]:
    path_key = "screenshot_path" if command == "screenshot" else "video_path"
    captures: List[Dict[str, Any]] = []
    for result in results:
        entry: Dict[str, Any] = {
            "device": result.get("device"),
            "viewport": result.get("viewport"),
            "status": result.get("status"),
            path_key: result.get(path_key),
            "capture_route_slug": result.get("capture_route_slug"),
            "capture_dir": result.get("capture_dir"),
            "capture_default": result.get("capture_default"),
        }
        if command == "screenshot":
            entry["screenshot_prep"] = result.get("screenshot_prep")
            entry["capture_hint"] = result.get("capture_hint")
        else:
            entry["scroll_steps"] = result.get("scroll_steps")
            entry["record_prep"] = result.get("record_prep")
            entry["scroll_mode"] = result.get("scroll_mode")
            entry["scroll_steps_performed"] = result.get("scroll_steps_performed")
            entry["error"] = result.get("error")
        captures.append(entry)

    all_ok = all(result.get("status") == "success" for result in results)
    any_ok = any(result.get("status") == "success" for result in results)
    status = "success" if all_ok else ("partial_failure" if any_ok else "error")
    primary = next(
        (result for result in results if result.get("device") == "desktop" and result.get("status") == "success"),
        None,
    )
    if primary is None:
        primary = next((result for result in results if result.get("status") == "success"), results[0])

    merged: Dict[str, Any] = {
        "status": status,
        "multi_device": True,
        "captures": captures,
        "title": primary.get("title"),
        "url": primary.get("url"),
        "capture_dir": primary.get("capture_dir"),
        "session_hint": primary.get("session_hint"),
    }
    if command == "screenshot":
        merged["auth_state"] = primary.get("auth_state")
        merged["full_page"] = primary.get("full_page")
        merged["screenshot_path"] = primary.get("screenshot_path")
        merged["capture_hint"] = primary.get("capture_hint")
    else:
        merged["video_path"] = primary.get("video_path")
        merged["scroll_steps"] = primary.get("scroll_steps")
        merged["scroll_mode"] = primary.get("scroll_mode")
        merged["scroll_steps_performed"] = primary.get("scroll_steps_performed")
    return merged


def resolve_viewport(device: Optional[str], viewport_raw: str) -> Dict[str, int]:
    if device:
        preset = DEVICE_PRESETS.get(device.lower())
        if not preset:
            raise ValueError(f"Unknown device preset: {device}. Use: {', '.join(DEVICE_PRESETS)}")
        return dict(preset)
    return parse_viewport(viewport_raw)


def parse_viewport(raw: Optional[str]) -> Dict[str, int]:
    if not raw:
        return {"width": 1280, "height": 800}
    match = re.match(r"^(\d+)x(\d+)$", raw.strip())
    if not match:
        raise ValueError("Viewport must look like 1280x800")
    return {"width": int(match.group(1)), "height": int(match.group(2))}


async def goto_with_retry(page: Page, url: str, timeout: int, retries: int, wait_until: str = "domcontentloaded") -> None:
    last_err: Optional[Exception] = None
    for attempt in range(max(1, retries)):
        try:
            await page.goto(url, wait_until=wait_until, timeout=timeout)
            return
        except Exception as e:
            last_err = e
            if attempt + 1 < retries:
                await asyncio.sleep(min(2 ** attempt, 4))
    if last_err:
        raise last_err


async def finalize_video(page: Page, output_path: Path) -> Optional[str]:
    video = page.video
    if not video:
        return None
    output_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        await video.save_as(str(output_path))
    except Exception:
        raw = await video.path()
        if raw and Path(raw).exists():
            Path(raw).replace(output_path)
        else:
            return None
    return str(output_path) if output_path.exists() else None


async def smooth_scroll_viewport_step(page: Page, step_px: int, duration_ms: int) -> bool:
    """Smoothly scroll one viewport step; return False if already at bottom."""
    result = await page.evaluate(
        """
        async ({ stepPx, durationMs }) => {
          const docHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
          const viewport = window.innerHeight;
          const startY = window.scrollY;
          const maxTarget = Math.max(0, docHeight - viewport);
          const targetY = Math.min(startY + stepPx, maxTarget);
          if (targetY <= startY + 1) {
            return { moved: false };
          }
          const dist = targetY - startY;
          const t0 = performance.now();
          await new Promise((resolve) => {
            function frame(now) {
              const t = Math.min(1, (now - t0) / Math.max(durationMs, 1));
              window.scrollTo(0, startY + dist * t);
              if (t < 1) {
                requestAnimationFrame(frame);
              } else {
                resolve();
              }
            }
            requestAnimationFrame(frame);
          });
          return { moved: true };
        }
        """,
        {"stepPx": step_px, "durationMs": duration_ms},
    )
    return bool(result.get("moved"))


async def scroll_page(
    page: Page,
    steps: int,
    delay_ms: int,
    full_page: bool,
    mode: str = "smooth",
    pause_ms: Optional[int] = None,
    scroll_duration_ms: Optional[int] = None,
) -> Dict[str, Any]:
    viewport = page.viewport_size or {"width": 1280, "height": 800}
    scroll_mode = mode if mode in SCROLL_MODES else "smooth"
    meta: Dict[str, Any] = {"scroll_mode": scroll_mode, "full_page": full_page}

    if scroll_mode == "step":
        step_px = max(1, viewport["height"])
        anim_ms = (
            scroll_duration_ms
            if scroll_duration_ms is not None
            else (delay_ms if delay_ms != 400 else STEP_SCROLL_DURATION_MS_DEFAULT)
        )
        anim_ms = max(anim_ms, 1)
        pause_ms_eff = pause_ms if pause_ms is not None else STEP_SCROLL_PAUSE_MS_DEFAULT
        performed = 0

        if full_page:
            max_steps = 100
            while performed < max_steps:
                doc_height = await page.evaluate(
                    "() => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
                )
                scroll_y = await page.evaluate("() => window.scrollY")
                if scroll_y + viewport["height"] >= doc_height - 1:
                    break
                moved = await smooth_scroll_viewport_step(page, step_px, anim_ms)
                if not moved:
                    break
                performed += 1
                await asyncio.sleep(pause_ms_eff / 1000.0)
        else:
            for _ in range(max(steps, 1)):
                moved = await smooth_scroll_viewport_step(page, step_px, anim_ms)
                if not moved:
                    break
                performed += 1
                await asyncio.sleep(pause_ms_eff / 1000.0)

        meta["scroll_steps_performed"] = performed
        meta["scroll_pause_ms"] = pause_ms_eff
        meta["scroll_duration_ms"] = anim_ms
        meta["scroll_easing"] = "linear"
        meta["scroll_step_px"] = step_px
        return meta

    if full_page:
        height = await page.evaluate(
            "() => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
        )
        step_px = max(1, height // max(steps, 1))
    else:
        step_px = max(1, viewport["height"] // 2)
    for _ in range(steps):
        await page.evaluate(f"window.scrollBy(0, {step_px})")
        await asyncio.sleep(delay_ms / 1000.0)

    meta["scroll_steps_performed"] = steps
    meta["scroll_delay_ms"] = delay_ms
    meta["scroll_step_px"] = step_px
    return meta


async def prefetch_lazy_content(
    page: Page,
    steps: int = 10,
    delay_ms: int = 120,
    *,
    full_document: bool = False,
    return_to_top: bool = True,
) -> int:
    """Scroll to trigger lazy-load observers. Returns iterations performed."""
    viewport = page.viewport_size or {"height": 800}
    step_px = viewport["height"] if full_document else max(1, viewport["height"] // 2)
    max_iter = 100 if full_document else max(steps, 1)
    performed = 0
    last_height = -1
    for _ in range(max_iter):
        height = await page.evaluate(
            "() => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
        )
        scroll_y = await page.evaluate("() => window.scrollY")
        if full_document and scroll_y + viewport["height"] >= height - 1 and height == last_height:
            break
        if not full_document and performed >= steps:
            break
        last_height = height
        await page.evaluate(f"window.scrollBy(0, {step_px})")
        performed += 1
        await asyncio.sleep(delay_ms / 1000.0)
    if return_to_top:
        await page.evaluate("window.scrollTo(0, 0)")
        await asyncio.sleep(0.15)
    return performed


async def prime_lazy_images(page: Page) -> Dict[str, int]:
    """Promote lazy images and scroll each pending asset into view before capture."""
    return await page.evaluate(
        """
        async () => {
          document.querySelectorAll("img[loading='lazy']").forEach((img) => {
            img.loading = "eager";
          });
          const isPending = (img) => {
            const src = img.currentSrc || img.src || "";
            if (/\\.svg($|\\?)/i.test(src)) {
              return !img.complete;
            }
            return !img.complete || img.naturalWidth === 0;
          };
          const pending = () => [...document.images].filter(isPending);
          for (const img of pending()) {
            img.scrollIntoView({ block: "center", inline: "nearest" });
            await new Promise((resolve) => setTimeout(resolve, 100));
          }
          await Promise.all(
            [...document.images].map((img) => {
              if (img.complete) {
                return img.decode?.().catch(() => {}) ?? Promise.resolve();
              }
              return new Promise((resolve) => {
                img.addEventListener("load", () => resolve(), { once: true });
                img.addEventListener("error", () => resolve(), { once: true });
              });
            })
          );
          return {
            pending_after_prime: pending().length,
            image_total: document.images.length,
          };
        }
        """
    )


def resolve_spa_ready(spa_ready: bool, no_spa_ready: bool, full_page: bool) -> bool:
    if no_spa_ready:
        return False
    return spa_ready or full_page


def build_capture_prep_opts(args: argparse.Namespace) -> Dict[str, Any]:
    full_page = bool(getattr(args, "full_page", False))
    spa_ready = resolve_spa_ready(
        bool(getattr(args, "spa_ready", False)),
        bool(getattr(args, "no_spa_ready", False)),
        full_page,
    )
    return {
        "spa_ready": spa_ready,
        "settle_ms": int(getattr(args, "settle_ms", 0) or 0),
        "disable_animations": bool(getattr(args, "disable_animations", False)),
        "prefetch_scroll": bool(getattr(args, "prefetch_scroll", False)) or (full_page and spa_ready),
        "full_page": full_page,
        "wait_for_selector": getattr(args, "wait_for_selector", None),
        "wait_for_function": getattr(args, "wait_for_function", None),
        "wait_until": args.wait_until,
    }


async def prepare_page_capture(page: Page, opts: Dict[str, Any], timeout: int) -> Dict[str, Any]:
    """Stabilize SPAs, animations, fonts, and lazy-loaded content before screenshot or record."""
    meta: Dict[str, Any] = {}
    spa_ready = bool(opts.get("spa_ready"))
    settle_ms = int(opts.get("settle_ms") or 0)
    disable_animations = bool(opts.get("disable_animations"))
    prefetch_scroll = bool(opts.get("prefetch_scroll"))
    wait_selector = opts.get("wait_for_selector")
    wait_function = opts.get("wait_for_function")

    if spa_ready:
        disable_animations = True
        prefetch_scroll = prefetch_scroll or bool(opts.get("full_page"))
        settle_ms = max(settle_ms, 600)
        meta["spa_ready"] = True

    if disable_animations:
        await page.add_style_tag(
            content=(
                "*, *::before, *::after {"
                "animation: none !important; transition: none !important;"
                "scroll-behavior: auto !important;"
                "}"
            )
        )
        meta["disable_animations"] = True

    await page.evaluate("window.scrollTo(0, 0)")

    try:
        await page.evaluate("() => document.fonts.ready")
        meta["fonts_ready"] = True
    except Exception:
        pass

    if spa_ready and opts.get("wait_until") != "networkidle":
        try:
            await page.wait_for_load_state("networkidle", timeout=min(timeout, 15000))
            meta["network_idle"] = True
        except Exception:
            meta["network_idle"] = False

    if prefetch_scroll:
        full_document = bool(opts.get("full_page"))
        prefetch_steps = await prefetch_lazy_content(
            page,
            steps=10,
            delay_ms=150 if full_document else 120,
            full_document=full_document,
        )
        meta["prefetch_scroll"] = True
        meta["prefetch_steps_performed"] = prefetch_steps
        meta["prefetch_full_document"] = full_document
        prime_meta = await prime_lazy_images(page)
        meta["images_pending_after_prime"] = prime_meta.get("pending_after_prime")
        meta["image_total"] = prime_meta.get("image_total")

    if wait_selector:
        await page.locator(wait_selector).wait_for(timeout=timeout)
        meta["wait_for_selector"] = wait_selector
    if wait_function:
        await page.wait_for_function(wait_function, timeout=timeout)
        meta["wait_for_function"] = True

    if settle_ms > 0:
        await asyncio.sleep(settle_ms / 1000.0)
        meta["settle_ms"] = settle_ms

    return meta


async def launch_context(
    p,
    user_data_dir: Path,
    headless: bool,
    viewport: Dict[str, int],
    record_video_dir: Optional[Path] = None,
    record_har_path: Optional[Path] = None,
) -> Tuple[BrowserContext, Optional[str]]:
    launch_args = [
        "--disable-blink-features=AutomationControlled",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-infobars",
        f"--window-size={viewport['width']},{viewport['height']}",
    ]
    ctx_kwargs: Dict[str, Any] = {
        "user_data_dir": str(user_data_dir),
        "headless": headless,
        "args": launch_args,
        "viewport": viewport,
        "locale": "ja-JP",
        "timezone_id": "Asia/Tokyo",
    }
    if record_video_dir:
        record_video_dir.mkdir(parents=True, exist_ok=True)
        ctx_kwargs["record_video_dir"] = str(record_video_dir)
        ctx_kwargs["record_video_size"] = viewport
    if record_har_path:
        record_har_path.parent.mkdir(parents=True, exist_ok=True)
        ctx_kwargs["record_har_path"] = str(record_har_path)
        ctx_kwargs["record_har_mode"] = "minimal"

    launch_note: Optional[str] = None
    try:
        return await p.chromium.launch_persistent_context(channel="chrome", **ctx_kwargs), launch_note
    except Exception as chrome_err:
        launch_note = f"chrome channel unavailable ({chrome_err}); trying bundled chromium"
        try:
            return await p.chromium.launch_persistent_context(**ctx_kwargs), launch_note
        except Exception as chromium_err:
            launch_note = (
                f"{launch_note}; bundled chromium failed ({chromium_err}); "
                "retrying without video/har recording"
            )
            ctx_kwargs.pop("record_video_dir", None)
            ctx_kwargs.pop("record_video_size", None)
            ctx_kwargs.pop("record_har_path", None)
            ctx_kwargs.pop("record_har_mode", None)
            return await p.chromium.launch_persistent_context(**ctx_kwargs), launch_note


def resolve_cdp_url(args: argparse.Namespace) -> Optional[str]:
    explicit = getattr(args, "cdp_url", None)
    if explicit:
        return explicit.strip()
    env_val = os.environ.get(CDP_URL_ENV)
    return env_val.strip() if env_val else None


def verify_cdp_profile(expected_dir: Path) -> Optional[str]:
    """Best-effort: warn when CDP Chrome may not use the expected profile directory."""
    if not expected_dir.exists():
        return None
    if _profile_in_use(expected_dir):
        return None
    return (
        f"CDP Chrome may not be using profile '{expected_dir.name}'; "
        f"launch with --user-data-dir=\"{expected_dir}\" or verify BROWSER_AGENT_CDP_URL."
    )


async def connect_or_launch_context(
    p,
    cdp_url: Optional[str],
    user_data_dir: Path,
    headless: bool,
    viewport: Dict[str, int],
    record_video_dir: Optional[Path] = None,
    record_har_path: Optional[Path] = None,
) -> Tuple[Optional[Any], BrowserContext, Optional[str]]:
    if cdp_url:
        browser = await p.chromium.connect_over_cdp(cdp_url)
        if browser.contexts:
            context = browser.contexts[0]
        else:
            context = await browser.new_context(
                viewport=viewport,
                locale="ja-JP",
                timezone_id="Asia/Tokyo",
            )
        return browser, context, f"connected_over_cdp:{cdp_url}"
    context, launch_note = await launch_context(
        p, user_data_dir, headless, viewport, record_video_dir, record_har_path
    )
    return None, context, launch_note


async def close_browser_session(
    browser: Optional[Any], context: BrowserContext, cdp_url: Optional[str]
) -> None:
    try:
        if cdp_url and browser is not None:
            await browser.close()
        else:
            await context.close()
    except Exception:
        pass


BATCH_COMMANDS = frozenset({"inspect", "screenshot", "eval"})


def load_batch_steps(batch_file: str) -> List[Dict[str, Any]]:
    path = Path(batch_file)
    if not path.is_file():
        raise ValueError(f"batch file not found: {batch_file}")
    steps = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(steps, list) or not steps:
        raise ValueError("batch file must be a non-empty JSON array")
    for idx, step in enumerate(steps):
        if not isinstance(step, dict):
            raise ValueError(f"batch step {idx + 1} must be a JSON object")
        cmd = step.get("command")
        if cmd not in BATCH_COMMANDS:
            raise ValueError(
                f"batch step {idx + 1} command must be one of: {', '.join(sorted(BATCH_COMMANDS))}"
            )
        if not step.get("url"):
            raise ValueError(f"batch step {idx + 1} requires url")
    return steps


def screenshot_opts_from_step(step: Dict[str, Any]) -> Dict[str, Any]:
    full_page = bool(step.get("full_page"))
    spa_ready = resolve_spa_ready(
        bool(step.get("spa_ready")),
        bool(step.get("no_spa_ready")),
        full_page,
    )
    return {
        "spa_ready": spa_ready,
        "settle_ms": int(step.get("settle_ms") or 0),
        "disable_animations": bool(step.get("disable_animations")),
        "prefetch_scroll": bool(step.get("prefetch_scroll")),
        "full_page": full_page,
        "wait_for_selector": step.get("wait_for_selector"),
        "wait_for_function": step.get("wait_for_function"),
        "wait_until": step.get("wait_until", "domcontentloaded"),
    }


async def run_screenshot_on_page(
    page: Page,
    step: Dict[str, Any],
    timeout: int,
    output_dir: Optional[str],
) -> Dict[str, Any]:
    out_path, capture_default = resolve_output_path(
        step.get("output"),
        url=page.url,
        ext=".png",
        output_dir=output_dir or step.get("output_dir"),
    )
    prep_opts = screenshot_opts_from_step(step)
    prep_meta = await prepare_page_capture(page, prep_opts, timeout)
    await page.screenshot(
        path=str(out_path),
        full_page=bool(step.get("full_page")),
        animations="disabled"
        if prep_opts.get("disable_animations") or prep_opts.get("spa_ready")
        else "allow",
    )
    title = await page.title()
    capture_hint = await page.evaluate(
        "() => document.querySelector('h1')?.innerText || document.title || ''"
    )
    text_preview = await page.evaluate(
        "() => (document.body?.innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 500)"
    )
    return {
        "status": "success",
        "title": title,
        "url": page.url,
        "auth_state": infer_auth_state(page.url, title, text_preview or ""),
        "screenshot_path": str(out_path),
        "capture_route_slug": slug_from_url(page.url),
        "full_page": bool(step.get("full_page")),
        "capture_dir": str(out_path.parent),
        "capture_default": capture_default,
        "screenshot_prep": prep_meta,
        "capture_hint": capture_hint,
        "session_hint": "Read the screenshot_path image in the agent session for visual follow-up",
    }


def finalize_screenshot_output(output: Dict[str, Any]) -> Dict[str, Any]:
    prep = output.get("screenshot_prep")
    if isinstance(prep, dict):
        apply_capture_prep_flags(output, prep)
    return output


async def run_batch_session(
    args: argparse.Namespace,
    user_data_dir: Path,
    cdp_url: Optional[str],
    session_start: float,
    lock_warning: Optional[str],
) -> Dict[str, Any]:
    steps = load_batch_steps(args.batch_file)
    headless = resolve_headless(args.profile, args.headless, args.headed)
    viewport = resolve_viewport(getattr(args, "device", None), args.viewport)
    wait_until = args.wait_until
    results: List[Dict[str, Any]] = []
    launch_note: Optional[str] = None

    async with async_playwright() as p:
        try:
            browser, context, launch_note = await connect_or_launch_context(
                p, cdp_url, user_data_dir, headless, viewport
            )
        except Exception as e:
            return {
                "status": "error",
                "error": str(e),
                "elapsed_ms": int((time.monotonic() - session_start) * 1000),
            }
        page = context.pages[0] if context.pages else await context.new_page()
        try:
            for idx, step in enumerate(steps):
                step_start = time.monotonic()
                step_out: Dict[str, Any] = {
                    "step": idx + 1,
                    "command": step["command"],
                    "name": step.get("name"),
                }
                try:
                    step_wait = step.get("wait_until", wait_until)
                    if step_wait not in WAIT_UNTIL_CHOICES:
                        step_wait = wait_until
                    target_url = normalize_url(step["url"])
                    await goto_with_retry(
                        page, target_url, args.timeout, args.retries, step_wait
                    )
                    if step_wait != "networkidle":
                        await asyncio.sleep(0.25)
                    if step["command"] == "inspect":
                        step_out.update(await extract_page_snapshot(page))
                    elif step["command"] == "screenshot":
                        step_out.update(
                            finalize_screenshot_output(
                                await run_screenshot_on_page(
                                    page,
                                    step,
                                    args.timeout,
                                    getattr(args, "output_dir", None),
                                )
                            )
                        )
                    else:
                        script_src = step.get("script")
                        if step.get("script_file"):
                            script_src = Path(step["script_file"]).read_text(encoding="utf-8")
                        if not script_src:
                            raise ValueError("eval step requires script or script_file")
                        eval_res = await page.evaluate(script_src)
                        step_out.update(
                            {
                                "status": "success",
                                "title": await page.title(),
                                "url": page.url,
                                "result": eval_res,
                            }
                        )
                except Exception as exc:
                    step_out["status"] = "error"
                    step_out["error"] = str(exc)
                step_out["step_elapsed_ms"] = int((time.monotonic() - step_start) * 1000)
                results.append(step_out)
        finally:
            await close_browser_session(browser, context, cdp_url)

    all_ok = all(r.get("status") == "success" for r in results)
    failed = [r for r in results if r.get("status") != "success"]
    login_steps = [
        {"step": r.get("step"), "name": r.get("name"), "url": r.get("url")}
        for r in results
        if r.get("auth_state") == "likely_login_or_challenge"
    ]
    output: Dict[str, Any] = {
        "status": "success" if all_ok else "partial_failure",
        "session_reused": True,
        "step_count": len(results),
        "steps_succeeded": len(results) - len(failed),
        "failed_step_count": len(failed),
        "results": results,
        "headless": headless,
        "wait_until": wait_until,
        "elapsed_ms": int((time.monotonic() - session_start) * 1000),
    }
    if login_steps:
        output["login_challenge_steps"] = login_steps
    if any(r.get("capture_incomplete") for r in results):
        output["capture_incomplete"] = True
    if cdp_url:
        output["cdp_url"] = cdp_url
        output["session_mode"] = "cdp_attach"
    else:
        output["session_mode"] = "single_launch"
    if launch_note:
        output["launch_note"] = launch_note
    if lock_warning:
        output["profile_lock_warning"] = lock_warning
    if getattr(args, "output_dir", None):
        output["captures_base"] = str(resolve_capture_dir(args.output_dir))
    if cdp_url and user_data_dir:
        cdp_warn = verify_cdp_profile(user_data_dir)
        if cdp_warn:
            output["cdp_profile_warning"] = cdp_warn
    return output


async def main() -> None:
    parser = argparse.ArgumentParser(description="Browser runner — real Chrome, persistent profiles")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common_args(p: argparse.ArgumentParser) -> None:
        p.add_argument("--url", required=True, help="Target URL")
        p.add_argument("--profile", default="temp", help="Profile: work, personal, temp, clean, or custom (default: temp)")
        p.add_argument("--headless", action="store_true", help="Force headless")
        p.add_argument("--headed", action="store_true", help="Force headed (recommended for SSO profiles)")
        p.add_argument("--timeout", type=int, default=30000, help="Navigation timeout in ms")
        p.add_argument("--viewport", default="1280x800", help="Viewport like 1280x800")
        p.add_argument("--device", choices=list(DEVICE_PRESETS.keys()), help="Preset: desktop, mobile, tablet")
        p.add_argument("--retries", type=int, default=2, help="Navigation retry count")
        p.add_argument(
            "--wait-until",
            default="domcontentloaded",
            choices=list(WAIT_UNTIL_CHOICES),
            help="Navigation wait condition (use networkidle for heavy SPAs)",
        )
        p.add_argument(
            "--network-output",
            help="Write network capture to .har (Playwright HAR) or .json (request/response log)",
        )
        p.add_argument(
            "--cdp-url",
            help=f"Attach to running Chrome via CDP (or set {CDP_URL_ENV}) instead of launching",
        )

    p_batch = subparsers.add_parser(
        "batch",
        help="Run inspect/screenshot/eval steps in one browser session (session reuse)",
    )
    p_batch.add_argument("--batch-file", required=True, help="JSON array of {command, url, ...} steps")
    p_batch.add_argument("--profile", default="temp", help="Profile: work, personal, temp, clean, or custom")
    p_batch.add_argument("--headless", action="store_true", help="Force headless")
    p_batch.add_argument("--headed", action="store_true", help="Force headed (recommended for SSO profiles)")
    p_batch.add_argument("--timeout", type=int, default=30000, help="Navigation timeout in ms")
    p_batch.add_argument("--viewport", default="1280x800", help="Viewport like 1280x800")
    p_batch.add_argument("--device", choices=list(DEVICE_PRESETS.keys()), help="Preset: desktop, mobile, tablet")
    p_batch.add_argument("--retries", type=int, default=2, help="Navigation retry count")
    p_batch.add_argument(
        "--wait-until",
        default="domcontentloaded",
        choices=list(WAIT_UNTIL_CHOICES),
        help="Default navigation wait for steps without their own wait_until",
    )
    p_batch.add_argument(
        "--output-dir",
        help="Base directory for default screenshot naming in batch steps",
    )
    p_batch.add_argument(
        "--cdp-url",
        help=f"Attach to running Chrome via CDP (or set {CDP_URL_ENV}) instead of launching",
    )

    p_inspect = subparsers.add_parser("inspect", help="Page snapshot (interactive elements + auth hint)")
    add_common_args(p_inspect)

    p_act = subparsers.add_parser("act", help="Execute action sequence")
    add_common_args(p_act)
    act_group = p_act.add_mutually_exclusive_group(required=True)
    act_group.add_argument("--actions", help="JSON array of actions (prefer --actions-file on Windows)")
    act_group.add_argument("--actions-file", help="Path to JSON file with action array")

    p_eval = subparsers.add_parser("eval", help="Evaluate JavaScript in page context")
    add_common_args(p_eval)
    eval_group = p_eval.add_mutually_exclusive_group(required=True)
    eval_group.add_argument("--script", help="JavaScript expression or function")
    eval_group.add_argument("--script-file", help="Path to .js file (prefer on Windows)")

    p_screenshot = subparsers.add_parser("screenshot", help="Capture screenshot")
    add_common_args(p_screenshot)
    p_screenshot.add_argument("--output", "-o", default=None, help="Output path (default: ~/.browser-agent/captures/YYYY-MM-DD/...)")
    p_screenshot.add_argument(
        "--output-dir",
        help="Base directory for default capture naming (or set BROWSER_AGENT_CAPTURE_DIR)",
    )
    p_screenshot.add_argument("--full-page", action="store_true")
    p_screenshot.add_argument(
        "--spa-ready",
        action="store_true",
        help="SPA preset (also auto-enabled with --full-page; use --no-spa-ready to disable)",
    )
    p_screenshot.add_argument(
        "--no-spa-ready",
        action="store_true",
        help="Disable auto SPA prep on --full-page",
    )
    p_screenshot.add_argument("--settle-ms", type=int, default=0, help="Extra wait before capture (ms)")
    p_screenshot.add_argument("--disable-animations", action="store_true", help="Inject CSS to disable animations/transitions")
    p_screenshot.add_argument(
        "--prefetch-scroll",
        action="store_true",
        help="Scroll page to trigger lazy-load handlers, then return to top",
    )
    p_screenshot.add_argument("--wait-for-selector", help="Wait for CSS selector before capture")
    p_screenshot.add_argument("--wait-for-function", help="Wait for JS expression to be truthy before capture")
    p_screenshot.add_argument(
        "--all-devices",
        action="store_true",
        help="Capture mobile, tablet, and desktop viewports",
    )
    p_screenshot.add_argument(
        "--devices",
        help="Comma-separated device presets (mobile, tablet, desktop)",
    )

    p_record = subparsers.add_parser("record", help="Record scroll video to local file")
    add_common_args(p_record)
    p_record.add_argument("--output", "-o", default=None, help="Output .webm path (default: ~/.browser-agent/captures/YYYY-MM-DD/...)")
    p_record.add_argument(
        "--output-dir",
        help="Base directory for default capture naming (or set BROWSER_AGENT_CAPTURE_DIR)",
    )
    p_record.add_argument("--scroll-steps", type=int, default=8)
    p_record.add_argument(
        "--scroll-delay",
        type=int,
        default=400,
        help="smooth mode: delay between steps (ms)",
    )
    p_record.add_argument(
        "--scroll-mode",
        choices=list(SCROLL_MODES),
        default="smooth",
        help="smooth: continuous equal steps; step: linear viewport scroll then pause",
    )
    p_record.add_argument(
        "--scroll-duration-ms",
        type=int,
        default=None,
        help=f"step mode: scroll animation duration per viewport (default: {STEP_SCROLL_DURATION_MS_DEFAULT})",
    )
    p_record.add_argument(
        "--scroll-pause-ms",
        type=int,
        default=None,
        help=f"step mode: pause at each screen (default: {STEP_SCROLL_PAUSE_MS_DEFAULT})",
    )
    p_record.add_argument("--full-page", action="store_true", help="Scroll through full document height")
    p_record.add_argument(
        "--spa-ready",
        action="store_true",
        help="SPA preset before scroll (auto with --full-page; use --no-spa-ready to disable)",
    )
    p_record.add_argument(
        "--no-spa-ready",
        action="store_true",
        help="Disable auto SPA prep on --full-page record",
    )
    p_record.add_argument("--settle-ms", type=int, default=0, help="Extra wait after prep before scroll (ms)")
    p_record.add_argument(
        "--prefetch-scroll",
        action="store_true",
        help="Force lazy-load prefetch before scroll (default on --full-page with SPA prep)",
    )
    p_record.add_argument(
        "--all-devices",
        action="store_true",
        help="Record mobile, tablet, and desktop viewports",
    )
    p_record.add_argument(
        "--devices",
        help="Comma-separated device presets (mobile, tablet, desktop)",
    )

    p_cookies = subparsers.add_parser("cookies", help="Export or import cookies for the profile")
    add_common_args(p_cookies)
    cookies_group = p_cookies.add_mutually_exclusive_group(required=True)
    cookies_group.add_argument("--export", "-o", dest="cookies_export", help="Write cookies JSON")
    cookies_group.add_argument("--import", "-i", dest="cookies_import", help="Read cookies JSON")

    args = parser.parse_args()
    session_start = time.monotonic()
    profile_lock_path: Optional[Path] = None
    profile_err = validate_profile_name(args.profile)
    if profile_err:
        emit_json(
            {
                "status": "error",
                "error": profile_err,
                "recommended_profile": "temp",
            },
            args,
            profile_lock_path,
        )
        return
    cdp_url = resolve_cdp_url(args)
    if args.command == "batch":
        try:
            load_batch_steps(args.batch_file)
        except (json.JSONDecodeError, ValueError) as err:
            output = {"status": "error", "error": str(err)}
            emit_json(output, args, profile_lock_path)
            return

    if args.command != "batch":
        try:
            device_plan, tag_device = resolve_capture_device_plan(args)
        except ValueError as plan_err:
            output = {"status": "error", "error": str(plan_err)}
            emit_json(output, args, profile_lock_path)
            return
    else:
        device_plan, tag_device = [None], False
    multi_device = len(device_plan) > 1
    headless = resolve_headless(args.profile, args.headless, args.headed)
    if args.command == "record" and not args.headless and not args.headed:
        headless = False

    headless_plan: List[bool] = [headless]
    if args.command == "record" and args.headless:
        headless_plan = [True, False]

    temp_dir_obj = None
    lock_warning: Optional[str] = None
    if args.profile in ("temp", "clean"):
        temp_dir_obj = tempfile.TemporaryDirectory(prefix="chrome_agent_temp_")
        user_data_dir = Path(temp_dir_obj.name)
    elif cdp_url:
        safe_profile = sanitize_profile_name(args.profile)
        user_data_dir = PROFILES_BASE / safe_profile
    else:
        safe_profile = sanitize_profile_name(args.profile)
        user_data_dir = PROFILES_BASE / safe_profile
        user_data_dir.mkdir(parents=True, exist_ok=True)
        profile_lock_path, lock_err = acquire_profile_lock(user_data_dir)
        if lock_err:
            output = {"status": "error", "error": lock_err}
            emit_json(output, args, profile_lock_path)
            return
        lock_warning = cleanup_singleton_locks(user_data_dir)

    if args.command == "batch":
        output = await run_batch_session(args, user_data_dir, cdp_url, session_start, lock_warning)
        if temp_dir_obj:
            try:
                temp_dir_obj.cleanup()
            except Exception:
                pass
        emit_json(output, args, profile_lock_path)
        return

    output: Dict[str, Any] = {"status": "error"}
    device_results: List[Dict[str, Any]] = []
    record_har_path: Optional[Path] = None
    network_log: List[Dict[str, Any]] = []
    launch_note: Optional[str] = None
    if getattr(args, "network_output", None):
        net_path = Path(args.network_output).resolve()
        if net_path.suffix.lower() == ".har":
            record_har_path = net_path
        else:
            net_path.parent.mkdir(parents=True, exist_ok=True)

    capture_device_iterations = device_plan if args.command in ("screenshot", "record") else [None]

    async with async_playwright() as p:
        connect_failed = False
        for device_idx, device_name in enumerate(capture_device_iterations):
            viewport = resolve_viewport(
                device_name if args.command in ("screenshot", "record") else getattr(args, "device", None),
                args.viewport,
            )
            record_video_dir: Optional[Path] = None
            if args.command == "record":
                day_dir = resolve_capture_dir(getattr(args, "output_dir", None)) / datetime.now().strftime("%Y-%m-%d")
                day_dir.mkdir(parents=True, exist_ok=True)
                record_video_dir = day_dir / ".browser-agent-videos"

            for attempt_idx, session_headless in enumerate(headless_plan):
                record_output_path: Optional[Path] = None
                record_page: Optional[Page] = None
                try:
                    cdp_browser, context, launch_note = await connect_or_launch_context(
                        p, cdp_url, user_data_dir, session_headless, viewport, record_video_dir, record_har_path
                    )
                except Exception as e:
                    output = {"status": "error", "error": str(e)}
                    connect_failed = True
                    break
                page = context.pages[0] if context.pages else await context.new_page()
                if getattr(args, "network_output", None) and not record_har_path and (not multi_device or device_idx == 0):
                    attach_network_listeners_context(context, network_log)

                try:
                    target_url = normalize_url(args.url)
                    await goto_with_retry(page, target_url, args.timeout, args.retries, args.wait_until)
                    if args.wait_until != "networkidle":
                        await asyncio.sleep(0.25)

                    if args.command == "inspect":
                        output = await extract_page_snapshot(page)
                    elif args.command == "screenshot":
                        device_tag = device_name if tag_device else None
                        out_path, capture_default = resolve_output_path(
                            args.output,
                            url=page.url,
                            ext=".png",
                            output_dir=getattr(args, "output_dir", None),
                            device=device_tag,
                        )
                        prep_opts = build_capture_prep_opts(args)
                        prep_meta = await prepare_page_capture(page, prep_opts, args.timeout)
                        await page.screenshot(
                            path=str(out_path),
                            full_page=args.full_page,
                            animations="disabled" if prep_opts.get("disable_animations") or prep_opts.get("spa_ready") else "allow",
                        )
                        title = await page.title()
                        capture_hint = await page.evaluate(
                            "() => document.querySelector('h1')?.innerText || document.title || ''"
                        )
                        text_preview = await page.evaluate(
                            "() => (document.body?.innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 500)"
                        )
                        output = {
                            "status": "success",
                            "title": title,
                            "url": page.url,
                            "auth_state": infer_auth_state(page.url, title, text_preview or ""),
                            "screenshot_path": str(out_path),
                            "capture_route_slug": slug_from_url(page.url),
                            "full_page": args.full_page,
                            "capture_dir": str(out_path.parent),
                            "capture_default": capture_default,
                            "screenshot_prep": prep_meta,
                            "capture_hint": capture_hint,
                            "session_hint": "Read the screenshot_path image in the agent session for visual follow-up",
                        }
                        apply_capture_prep_flags(output, prep_meta)
                    elif args.command == "act":
                        try:
                            actions_list = load_actions(args.actions, args.actions_file)
                        except (json.JSONDecodeError, ValueError) as err:
                            output = {"status": "error", "message": str(err)}
                            actions_list = []
                        if actions_list:
                            action_results, page = await execute_actions(page, context, actions_list)
                            snapshot = await extract_page_snapshot(page)
                            output = {
                                "status": "success" if all(r.get("status") == "success" for r in action_results) else "partial_failure",
                                "action_results": action_results,
                                "current_page": snapshot,
                            }
                    elif args.command == "eval":
                        script_src = load_script(args.script, args.script_file)
                        eval_res = await page.evaluate(script_src)
                        output = {
                            "status": "success",
                            "title": await page.title(),
                            "url": page.url,
                            "result": eval_res,
                        }
                    elif args.command == "record":
                        device_tag = device_name if tag_device else None
                        record_output_path, capture_default = resolve_output_path(
                            args.output,
                            url=page.url,
                            ext=".webm",
                            output_dir=getattr(args, "output_dir", None),
                            device=device_tag,
                        )
                        record_page = page
                        prep_meta = await prepare_page_capture(
                            page, build_capture_prep_opts(args), args.timeout
                        )
                        scroll_meta = await scroll_page(
                            page,
                            args.scroll_steps,
                            args.scroll_delay,
                            args.full_page,
                            mode=args.scroll_mode,
                            pause_ms=args.scroll_pause_ms,
                            scroll_duration_ms=args.scroll_duration_ms,
                        )
                        output = {
                            "status": "pending",
                            "title": await page.title(),
                            "url": page.url,
                            "scroll_steps": args.scroll_steps,
                            "record_prep": prep_meta,
                            **scroll_meta,
                            "video_path_pending": str(record_output_path),
                            "capture_route_slug": slug_from_url(page.url),
                            "capture_dir": str(record_output_path.parent),
                            "capture_default": capture_default,
                        }
                    elif args.command == "cookies":
                        if args.cookies_export:
                            export_path = Path(args.cookies_export).resolve()
                            export_path.parent.mkdir(parents=True, exist_ok=True)
                            cookies = await context.cookies()
                            export_path.write_text(
                                json.dumps(cookies, ensure_ascii=False, indent=2), encoding="utf-8"
                            )
                            output = {
                                "status": "success",
                                "url": page.url,
                                "cookie_count": len(cookies),
                                "export_path": str(export_path),
                                "sensitive_export": True,
                                "session_hint": "Never commit cookies JSON; treat export_path as secrets.",
                            }
                        else:
                            import_path = Path(args.cookies_import).resolve()
                            cookies_data = json.loads(import_path.read_text(encoding="utf-8"))
                            if not isinstance(cookies_data, list):
                                raise ValueError("Cookies JSON must be an array")
                            await context.add_cookies(cookies_data)
                            await page.reload(wait_until=args.wait_until)
                            stored = await context.cookies()
                            imported_names = {c.get("name") for c in cookies_data if c.get("name")}
                            verified_names = sorted(
                                {c["name"] for c in stored if c.get("name") in imported_names}
                            )
                            output = {
                                "status": "success",
                                "url": page.url,
                                "imported_count": len(cookies_data),
                                "verified_count": len(verified_names),
                                "verified_names": verified_names,
                            }
                except PlaywrightTimeoutError:
                    output = {"status": "error", "error": f"Timed out after {args.timeout}ms"}
                except ValueError as ve:
                    output = {"status": "error", "error": str(ve)}
                except Exception as e:
                    output = {"status": "error", "error": str(e)}
                finally:
                    await close_browser_session(cdp_browser, context, cdp_url)
                    if args.command == "record" and record_page and record_output_path:
                        saved_path = await finalize_video(record_page, record_output_path)
                        output = {
                            "status": "success" if saved_path else "error",
                            "title": output.get("title"),
                            "url": output.get("url"),
                            "video_path": saved_path,
                            "capture_route_slug": slug_from_url(
                                record_page.url if record_page else (output.get("url") or "")
                            ),
                            "capture_dir": str(record_output_path.parent) if record_output_path else None,
                            "capture_default": output.get("capture_default"),
                            "scroll_steps": output.get("scroll_steps"),
                            "record_prep": output.get("record_prep"),
                            "scroll_mode": output.get("scroll_mode"),
                            "scroll_steps_performed": output.get("scroll_steps_performed"),
                            "scroll_delay_ms": output.get("scroll_delay_ms"),
                            "scroll_duration_ms": output.get("scroll_duration_ms"),
                            "scroll_pause_ms": output.get("scroll_pause_ms"),
                            "scroll_easing": output.get("scroll_easing"),
                            "scroll_step_px": output.get("scroll_step_px"),
                            "full_page": output.get("full_page"),
                            "session_hint": "Attach or inspect video_path for scroll review",
                            "error": None if saved_path else "Video file was not produced; retry with --headed",
                        }
                        prep = output.get("record_prep")
                        if isinstance(prep, dict):
                            apply_capture_prep_flags(output, prep)

                output["headless"] = session_headless
                if cdp_url:
                    output["cdp_url"] = cdp_url
                    output["session_mode"] = "cdp_attach"
                if attempt_idx > 0 and output.get("status") == "success":
                    output["record_fallback"] = "headed_after_headless_failed"
                if args.command != "record" or output.get("status") == "success" or attempt_idx == len(headless_plan) - 1:
                    break

            if connect_failed:
                break

            if args.command in ("screenshot", "record"):
                output["device"] = device_name if device_name else "custom"
                output["viewport"] = dict(viewport)
                device_results.append(dict(output))
            else:
                break

    if multi_device and device_results:
        output = merge_multi_device_captures(device_results, args.command)

    if temp_dir_obj:
        try:
            temp_dir_obj.cleanup()
        except Exception:
            pass

    if lock_warning:
        output["profile_lock_warning"] = lock_warning
    if launch_note:
        output["launch_note"] = launch_note
    output["wait_until"] = args.wait_until
    if getattr(args, "network_output", None):
        net_path = Path(args.network_output).resolve()
        if record_har_path:
            output["network_output"] = str(net_path) if net_path.exists() else None
            output["network_format"] = "har"
        elif network_log:
            net_path.write_text(json.dumps(network_log, ensure_ascii=False, indent=2), encoding="utf-8")
            output["network_output"] = str(net_path)
            output["network_format"] = "json"
            output["network_event_count"] = len(network_log)
    output["elapsed_ms"] = int((time.monotonic() - session_start) * 1000)
    if args.command in ("screenshot", "record"):
        output["captures_base"] = str(resolve_capture_dir(getattr(args, "output_dir", None)))
    if cdp_url and user_data_dir.exists():
        cdp_warn = verify_cdp_profile(user_data_dir)
        if cdp_warn:
            output["cdp_profile_warning"] = cdp_warn
    emit_json(output, args, profile_lock_path)


if __name__ == "__main__":
    asyncio.run(main())
