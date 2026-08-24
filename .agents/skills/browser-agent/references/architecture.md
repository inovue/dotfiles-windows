# 🏗️ Browser Agent Skill Architecture & Deep Dive

This document details the architectural decisions and fail-safe designs implemented in the `browser-agent` skill.

---

## 1. Multi-Layer Anti-Detection Strategy
- **Channel Binding**: Defaults to `channel="chrome"`, utilizing the host machine's genuine Chrome binary and complete V8/Blink stack.
- **Flag Masking**: Employs `--disable-blink-features=AutomationControlled` to strip runtime automation signatures.
- **Locale & Timezone Alignment**: Configures `ja-JP` and `Asia/Tokyo` uniformly across CDP contexts.

---

## 2. Process Lifecycle & Concurrency Shield
- **Singleton Lock Purging**: Proactively purges stale lockfiles (`SingletonLock`, `SingletonCookie`) left by abnormal process terminations.
- **Isolated Profile Directories**: Keeps `work`, `personal`, and custom profiles strictly isolated to prevent session contamination.
- **Clean Ephemeral Modes**: Creates auto-destroyed temporary profiles for stateless, zero-cookie browsing.

---

## 3. High-Speed Accessibility (a11y) Extraction
- Rather than transmitting multi-megabyte raw HTML or token-heavy screenshots, extracts the top interactive elements and text excerpts directly from the browser's accessibility tree.
- Dramatically lowers token usage (90% reduction) and ensures sub-second LLM reasoning.
