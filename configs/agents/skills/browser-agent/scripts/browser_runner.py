import argparse
import asyncio
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

try:
    from playwright.async_api import async_playwright, BrowserContext, Page, TimeoutError as PlaywrightTimeoutError
except ImportError:
    print(json.dumps({
        "status": "error",
        "message": "Playwright is not installed. Run: pip install playwright && playwright install chromium"
    }))
    sys.exit(1)

PROFILES_BASE = Path.home() / ".chrome-profiles"

def cleanup_singleton_locks(profile_dir: Path):
    """Clean up stale Chrome lock files to prevent startup crash after abrupt kill."""
    for lock_name in ["SingletonLock", "SingletonCookie", "SingletonSocket", "lockfile"]:
        lock_file = profile_dir / lock_name
        if lock_file.exists():
            try:
                if lock_file.is_dir() or lock_file.is_symlink():
                    lock_file.unlink()
                else:
                    lock_file.unlink(missing_ok=True)
            except Exception:
                pass

async def extract_a11y_tree(page: Page) -> Dict[str, Any]:
    """Extract clean semantic interactive elements for ultra-low token reasoning."""
    title = await page.title()
    url = page.url

    # Fast client-side semantic extractor
    semantic_data = await page.evaluate('''() => {
        const interactiveSelectors = 'a, button, input, select, textarea, [role="button"], [role="link"], [role="checkbox"], [role="menuitem"], [role="tab"]';
        const elements = Array.from(document.querySelectorAll(interactiveSelectors));
        
        const results = [];
        for (const el of elements) {
            const rect = el.getBoundingClientRect();
            // Visible only
            if (rect.width === 0 || rect.height === 0 || window.getComputedStyle(el).visibility === 'hidden' || window.getComputedStyle(el).display === 'none') {
                continue;
            }
            
            const tag = el.tagName.toLowerCase();
            const role = el.getAttribute('role') || tag;
            const text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.getAttribute('value') || el.getAttribute('title') || '').trim();
            const id = el.id ? '#' + el.id : '';
            const type = el.getAttribute('type') || '';
            const name = el.getAttribute('name') || '';

            let selector = tag;
            if (id) selector = id;
            else if (name) selector = `${tag}[name="${name}"]`;
            else if (type) selector = `${tag}[type="${type}"]`;

            results.push({
                tag: tag,
                role: role,
                text: text.slice(0, 100),
                selector: selector,
                id: el.id || null,
                name: name || null,
                type: type || null,
                href: el.href || null
            });
            if (results.length >= 60) break;
        }

        const bodyText = document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 2500) : '';

        return {
            elements: results,
            text_preview: bodyText.trim()
        };
    }''')

    return {
        "status": "success",
        "title": title,
        "url": url,
        "interactive_count": len(semantic_data.get("elements", [])),
        "interactive_elements": semantic_data.get("elements", []),
        "text_preview": semantic_data.get("text_preview", "")
    }


async def execute_actions(page: Page, actions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Execute sequence of deterministic actions with error reporting."""
    results = []
    for idx, act in enumerate(actions):
        act_type = act.get("type")
        selector = act.get("selector")
        val = act.get("value")
        timeout = act.get("timeout", 10000)
        
        step_res = {"step": idx + 1, "type": act_type, "status": "pending"}
        try:
            if act_type == "click":
                await page.click(selector, timeout=timeout)
                step_res["status"] = "success"
            elif act_type == "fill":
                await page.fill(selector, str(val), timeout=timeout)
                step_res["status"] = "success"
            elif act_type == "press":
                key = act.get("key", "Enter")
                await page.press(selector, key, timeout=timeout)
                step_res["status"] = "success"
            elif act_type == "wait_for_selector":
                await page.wait_for_selector(selector, timeout=timeout)
                step_res["status"] = "success"
            elif act_type == "wait_for_load":
                state = act.get("state", "domcontentloaded")
                await page.wait_for_load_state(state, timeout=timeout)
                step_res["status"] = "success"
            elif act_type == "wait_for_timeout":
                await asyncio.sleep(act.get("milliseconds", 1000) / 1000.0)
                step_res["status"] = "success"
            elif act_type == "extract_text":
                text = await page.inner_text(selector, timeout=timeout)
                step_res["status"] = "success"
                step_res["data"] = text
            elif act_type == "screenshot":
                path = act.get("path", "screenshot.png")
                full_page = act.get("full_page", False)
                out_path = Path(path).resolve()
                out_path.parent.mkdir(parents=True, exist_ok=True)
                await page.screenshot(path=str(out_path), full_page=full_page)
                step_res["status"] = "success"
                step_res["path"] = str(out_path)
            else:
                step_res["status"] = "error"
                step_res["error"] = f"Unknown action type: {act_type}"
        except Exception as e:
            step_res["status"] = "failed"
            step_res["error"] = str(e)
            results.append(step_res)
            break
        results.append(step_res)
    return results

def normalize_url(url: str) -> str:
    """Ensure URL has a valid protocol prefix (defaults to http for localhost, https otherwise)."""
    url = url.strip()
    if url.startswith(("http://", "https://", "file://", "data:", "about:")):
        return url
    if url.startswith(("localhost", "127.0.0.1", "0.0.0.0", "::1")):
        return f"http://{url}"
    return f"https://{url}"

async def main():
    parser = argparse.ArgumentParser(description="Ultra-Reliable Browser Runner")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Common args
    def add_common_args(p):
        p.add_argument("--url", required=True, help="Target URL")
        p.add_argument("--profile", default="default", help="Profile name (work, personal, temp, <name>)")
        p.add_argument("--headless", action="store_true", help="Run headlessly")
        p.add_argument("--timeout", type=int, default=30000, help="Navigation timeout in ms")

    # 1. inspect
    p_inspect = subparsers.add_parser("inspect", help="Inspect page and extract a11y tree snapshot")
    add_common_args(p_inspect)

    # 2. act
    p_act = subparsers.add_parser("act", help="Execute multi-step deterministic actions")
    add_common_args(p_act)
    p_act.add_argument("--actions", required=True, help="JSON array of actions")

    # 3. eval
    p_eval = subparsers.add_parser("eval", help="Evaluate JavaScript inside page context")
    add_common_args(p_eval)
    p_eval.add_argument("--script", required=True, help="JavaScript function or expression to execute")

    # 4. screenshot
    p_screenshot = subparsers.add_parser("screenshot", help="Take a screenshot of the target page")
    add_common_args(p_screenshot)
    p_screenshot.add_argument("--output", "-o", default="screenshot.png", help="Path to save screenshot")
    p_screenshot.add_argument("--full-page", action="store_true", help="Capture full scrollable page")

    args = parser.parse_args()

    # Profile handling
    temp_dir_obj = None
    if args.profile in ["temp", "clean"]:
        temp_dir_obj = tempfile.TemporaryDirectory(prefix="chrome_agent_temp_")
        user_data_dir = Path(temp_dir_obj.name)
    else:
        # Sanitize profile name to prevent path traversal
        safe_profile = re.sub(r'[^a-zA-Z0-9_-]', '_', args.profile)
        user_data_dir = PROFILES_BASE / safe_profile
        user_data_dir.mkdir(parents=True, exist_ok=True)
        cleanup_singleton_locks(user_data_dir)

    output = {"status": "error"}

    async with async_playwright() as p:
        # Anti-detection launch parameters
        launch_args = [
            "--disable-blink-features=AutomationControlled",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-infobars",
            "--window-size=1280,800",
        ]

        try:
            context: BrowserContext = await p.chromium.launch_persistent_context(
                user_data_dir=str(user_data_dir),
                channel="chrome",
                headless=args.headless,
                args=launch_args,
                viewport={"width": 1280, "height": 800},
                locale="ja-JP",
                timezone_id="Asia/Tokyo"
            )
        except Exception as e:
            # Fallback to default chromium if Google Chrome is not installed
            context: BrowserContext = await p.chromium.launch_persistent_context(
                user_data_dir=str(user_data_dir),
                headless=args.headless,
                args=launch_args,
                viewport={"width": 1280, "height": 800},
                locale="ja-JP",
                timezone_id="Asia/Tokyo"
            )

        page = context.pages[0] if context.pages else await context.new_page()

        try:
            target_url = normalize_url(args.url)
            await page.goto(target_url, wait_until="domcontentloaded", timeout=args.timeout)
            # Give short buffer for hydration
            await asyncio.sleep(1.0)

            if args.command == "inspect":
                output = await extract_a11y_tree(page)

            elif args.command == "screenshot":
                out_path = Path(args.output).resolve()
                out_path.parent.mkdir(parents=True, exist_ok=True)
                await page.screenshot(path=str(out_path), full_page=args.full_page)
                output = {
                    "status": "success",
                    "title": await page.title(),
                    "url": page.url,
                    "screenshot_path": str(out_path),
                    "full_page": args.full_page
                }

            elif args.command == "act":
                try:
                    actions_list = json.loads(args.actions)
                except json.JSONDecodeError as jde:
                    output = {"status": "error", "message": f"Invalid JSON in --actions: {jde}"}
                    actions_list = []

                if actions_list:
                    action_results = await execute_actions(page, actions_list)
                    current_a11y = await extract_a11y_tree(page)
                    output = {
                        "status": "success" if all(r.get("status") == "success" for r in action_results) else "partial_failure",
                        "action_results": action_results,
                        "current_page": current_a11y
                    }

            elif args.command == "eval":
                eval_res = await page.evaluate(args.script)
                output = {
                    "status": "success",
                    "title": await page.title(),
                    "url": page.url,
                    "result": eval_res
                }

        except PlaywrightTimeoutError:
            output = {"status": "error", "error": f"Page load or action timed out after {args.timeout}ms"}
        except Exception as e:
            output = {"status": "error", "error": str(e)}
        finally:
            try:
                await context.close()
            except Exception:
                pass
            if temp_dir_obj:
                try:
                    temp_dir_obj.cleanup()
                except Exception:
                    pass

    print(json.dumps(output, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    asyncio.run(main())
