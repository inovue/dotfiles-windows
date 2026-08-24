---
name: modern-cli-expert
description: >-
  Expert guide and practical recipes for high-speed modern CLI utilities (ast-grep,
  sd, jaq/jq, xh, procs, difftastic, ripgrep, fd, hyperfine). Use when performing
  complex code refactoring, structural AST search/replace, API testing, process diagnosis,
  performance benchmarking, or advanced data stream processing.
---

# Modern CLI Expert Workflows & Advanced Recipes

This skill equips agents with precise, high-performance command patterns for complex development tasks using compiled Rust/Go utilities on Windows.

---

## 🌳 1. Structural AST Code Refactoring (`ast-grep`)

Use `ast-grep` (`ast-grep` or `sg`) for syntax-tree aware refactoring without regex parsing errors.

### Recipes:
- **Search for function calls across TypeScript/JavaScript**:
  ```bash
  ast-grep -p 'console.log($$$ARGS)' --lang ts
  ```
- **Rewrite function patterns in-place**:
  ```bash
  ast-grep -p 'fetch($URL, { method: "POST", body: $BODY })' -r 'apiClient.post($URL, $BODY)' -U --lang ts
  ```
- **Inspect match details in JSON**:
  ```bash
  ast-grep -p 'class $NAME extends $BASE { $$$BODY }' --json
  ```

---

## ⚡ 2. High-Speed In-Place Regex Substitution (`sd`)

Use `sd` for instant, clean regex find-and-replace across files without escaping headaches.

### Recipes:
- **Literal or regex replacement in single file**:
  ```bash
  sd 'old_function_name' 'new_function_name' src/lib.rs
  ```
- **Regex with capture groups**:
  ```bash
  sd 'import \{ (.*) \} from "lodash"' 'import { $1 } from "lodash-es"' src/index.ts
  ```
- **Multi-file substitution via `fd` + `sd`**:
  ```bash
  fd -e ts -e js -x sd 'const API_URL = ".*"' 'const API_URL = process.env.API_URL'
  ```

---

## 🌐 3. High-Speed API Querying & Testing (`xh`)

Use `xh` as the fastest, auto-formatting REST/JSON client (replaces heavy curl boilerplate).

### Recipes:
- **GET request with query parameters**:
  ```bash
  xh GET https://httpbin.org/get search==antigravity limit==10
  ```
- **POST JSON payload (auto-encoded)**:
  ```bash
  xh POST https://httpbin.org/post name="Antigravity" enabled:=true count:=42
  ```
- **Bearer Token Auth & Custom Headers**:
  ```bash
  xh GET https://api.github.com/user "Authorization:Bearer $TOKEN" "Accept:application/vnd.github.v3+json"
  ```

---

## 📊 4. Zero-Dependency Stream JSON Processing (`jaq` / `jq`)

Use `jaq` (Rust, 10x-30x faster) or `jq` for stream JSON transformations.

### Recipes:
- **Extract specific keys and values**:
  ```bash
  jaq -r '.users[] | select(.active == true) | .email' data.json
  ```
- **Construct transformed JSON objects**:
  ```bash
  jaq '{ total: length, active: [.[] | select(.active)] | length }' data.json
  ```

---

## 🔍 5. Structural Syntax Diffing (`difftastic` / `difft`)

Use `difft` for structural AST diff comparison between two files.

### Recipes:
- **Compare two files with AST awareness**:
  ```bash
  difft --color=never src/v1.rs src/v2.rs
  ```

---

## ⚙️ 6. Process & Port Inspection (`procs`)

Use `procs` for instant PID, hierarchy, and port binding resolution.

### Recipes:
- **Find process listening on specific port**:
  ```bash
  procs :8080
  ```
- **Search process tree by name**:
  ```bash
  procs node
  ```

---

## ⏱️ 7. CLI Benchmarking & Profiling (`hyperfine`)

Use `hyperfine` for statistical execution performance measurement.

### Recipes:
- **Compare two alternative implementations**:
  ```bash
  hyperfine --warmup 3 'rg -n "pattern" src/' 'powershell -Command "Select-String ..."'
  ```
