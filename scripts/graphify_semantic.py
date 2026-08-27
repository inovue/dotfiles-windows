#!/usr/bin/env python3
"""Session-bound semantic graph plumbing (no headless LLM).

prepare   — detect docs/images/papers (filtered), consult SHA cache, write uncached list
merge     — cache + .graphify_semantic.json + .graphify_chunk_*.json → graph.json
rehydrate — replay cached semantic onto a fresh AST graph (no new LLM output)
status    — print SHA-uncached count and INFERRED edge share

The host agent writes graphify-out/.graphify_semantic.json or chunk JSON; this
script never calls an API. Invoke via:
uv tool run --from graphifyy python scripts/graphify_semantic.py
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SPEC = (
    REPO_ROOT
    / "configs"
    / "agents"
    / "skills"
    / "graphify-builder"
    / "references"
    / "extraction-spec.md"
)
OUT_DIRNAME = "graphify-out"
UNCACHED_NAME = ".graphify_uncached.txt"
CACHED_NAME = ".graphify_cached.json"
SEMANTIC_NAME = ".graphify_semantic.json"
CHUNK_GLOB = ".graphify_chunk_*.json"
LABELS_NAME = ".graphify_target_labels.txt"
NEEDS_UPDATE = "needs_update"
TARGET_LABELS_CAP = 200
SKIP_SUFFIXES = {".yml", ".yaml"}
POINTER_MAX_LINES = 5
POINTER_NEEDLE = "@AGENTS.md"


def _out(root: Path) -> Path:
    d = root / OUT_DIRNAME
    d.mkdir(parents=True, exist_ok=True)
    return d


def _spec_path(explicit: str | None, root: Path) -> Path:
    if explicit:
        return Path(explicit).resolve()
    env = __import__("os").environ.get("GRAPHIFY_EXTRACTION_SPEC")
    if env:
        return Path(env).resolve()
    candidate = root / "configs/agents/skills/graphify-builder/references/extraction-spec.md"
    if candidate.is_file():
        return candidate
    return DEFAULT_SPEC


def _rel(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"nodes": [], "edges": [], "hyperedges": []}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return {"nodes": [], "edges": [], "hyperedges": []}
    data.setdefault("nodes", [])
    data.setdefault("edges", [])
    data.setdefault("hyperedges", [])
    return data


def _combine(*parts: dict[str, Any], ast_first: bool = True) -> dict[str, Any]:
    """Merge extraction dicts. First writer wins on node id (AST should go first)."""
    nodes: dict[str, dict] = {}
    edges: list[dict] = []
    hyper: list[dict] = []
    ordered = parts if ast_first else parts
    for part in ordered:
        for node in part.get("nodes") or []:
            nid = node.get("id")
            if nid and nid not in nodes:
                nodes[nid] = node
        edges.extend(part.get("edges") or [])
        hyper.extend(part.get("hyperedges") or [])
    return {
        "nodes": list(nodes.values()),
        "edges": edges,
        "hyperedges": hyper,
        "input_tokens": 0,
        "output_tokens": 0,
    }


def _is_under_out(root: Path, path: Path) -> bool:
    try:
        path.resolve().relative_to((root / OUT_DIRNAME).resolve())
        return True
    except ValueError:
        return False


def _is_pointer_markdown(path: Path) -> bool:
    """True when the file is an @AGENTS.md pointer (≤5 lines), not real docs."""
    if path.suffix.lower() not in {".md", ".markdown"}:
        return False
    try:
        text = path.read_text(encoding="utf-8-sig")
    except OSError:
        return False
    if POINTER_NEEDLE not in text:
        return False
    return len(text.splitlines()) <= POINTER_MAX_LINES


def _keep_semantic_path(root: Path, path: Path) -> bool:
    if _is_under_out(root, path):
        return False
    if path.suffix.lower() in SKIP_SUFFIXES:
        return False
    if _is_pointer_markdown(path):
        return False
    return True


def _semantic_paths(root: Path) -> tuple[list[str], list[str], dict[str, Any]]:
    """Detect docs/images, then drop graphify-out/, yaml, and pointer markdown."""
    from graphify.detect import detect

    result = detect(root)
    files = result.get("files") or {}
    keep: list[str] = []
    skipped_pointers: list[str] = []
    for key in ("document", "paper", "image"):
        for item in files.get(key) or []:
            path = Path(item).resolve()
            if _is_pointer_markdown(path):
                skipped_pointers.append(str(path))
                continue
            if not _keep_semantic_path(root, path):
                continue
            keep.append(str(path))
    return keep, skipped_pointers, result


def _cache_skipped_pointers(root: Path, spec: Path, pointers: list[str]) -> int:
    """SHA-cache pointer files as empty extract groups so they never reappear."""
    from graphify.cache import save_semantic_cache

    if not pointers or not spec.is_file():
        return 0
    nodes = []
    for abs_path in pointers:
        rel = _rel(root, Path(abs_path))
        stem = Path(abs_path).stem.lower()
        safe = "".join(ch if ch.isalnum() else "_" for ch in stem)
        nodes.append(
            {
                "id": f"skip_pointer_{safe}",
                "label": "AGENTS.md pointer (skip extract)",
                "file_type": "concept",
                "source_file": rel,
                "source_location": "L1",
            }
        )
    return save_semantic_cache(
        nodes,
        [],
        [],
        root=root,
        prompt_file=spec,
        allowed_source_files=pointers,
    )


def _write_target_labels(root: Path) -> None:
    """Write existing graph.json labels for extractor edge targets."""
    graph_path = _out(root) / "graph.json"
    counts: Counter[str] = Counter()
    if graph_path.is_file():
        try:
            data = json.loads(graph_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            data = {}
        for node in data.get("nodes") or []:
            if not isinstance(node, dict):
                continue
            label = str(node.get("label") or node.get("id") or "").strip()
            if label:
                counts[label] += 1
    ordered = [label for label, _ in counts.most_common(TARGET_LABELS_CAP)]
    text = "\n".join(ordered) + ("\n" if ordered else "")
    (_out(root) / LABELS_NAME).write_text(text, encoding="utf-8")


def _load_agent_semantic(out: Path) -> dict[str, Any]:
    """Union .graphify_semantic.json + .graphify_chunk_*.json (first id wins)."""
    parts: list[dict[str, Any]] = []
    semantic_path = out / SEMANTIC_NAME
    if semantic_path.is_file():
        parts.append(_load_json(semantic_path))
    for chunk in sorted(out.glob(CHUNK_GLOB)):
        parts.append(_load_json(chunk))
    if not parts:
        return {"nodes": [], "edges": [], "hyperedges": []}
    return _combine(*parts)


def _payload_nonempty(payload: dict[str, Any]) -> bool:
    return bool(payload.get("nodes") or payload.get("edges") or payload.get("hyperedges"))


def _ensure_ast_graph(root: Path) -> Path:
    """Return graph.json, running `graphify update` if it is missing."""
    import shutil
    import subprocess

    graph_path = _out(root) / "graph.json"
    if graph_path.is_file():
        return graph_path
    exe = shutil.which("graphify")
    if not exe:
        print("error: graphify executable not on PATH", file=sys.stderr)
        raise FileNotFoundError("graphify")
    print("graph.json missing — running graphify update (AST)...")
    proc = subprocess.run([exe, "update", "."], cwd=root)
    if proc.returncode != 0 or not graph_path.is_file():
        print("error: graphify update failed; cannot merge semantic layer", file=sys.stderr)
        raise RuntimeError("graphify update failed")
    return graph_path


def _add_semantic_layer(graph: Any, semantic: dict[str, Any]) -> Any:
    """Add concept nodes/edges without dropping markdown/code AST nodes."""
    for node in semantic.get("nodes") or []:
        nid = node.get("id")
        if not nid or nid in graph:
            continue
        attrs = {key: val for key, val in node.items() if key != "id"}
        graph.add_node(nid, **attrs)

    seen_edges = {
        (src, tgt, data.get("relation"))
        for src, tgt, data in graph.edges(data=True)
    }
    for edge in semantic.get("edges") or []:
        src, tgt = edge.get("source"), edge.get("target")
        if not src or not tgt:
            continue
        if src not in graph:
            graph.add_node(src, label=str(src), file_type="concept")
        if tgt not in graph:
            graph.add_node(tgt, label=str(tgt), file_type="concept")
        rel = edge.get("relation")
        key = (src, tgt, rel)
        if key in seen_edges:
            continue
        attrs = {k: v for k, v in edge.items() if k not in ("source", "target")}
        graph.add_edge(src, tgt, **attrs)
        seen_edges.add(key)

    hypers = list(graph.graph.get("hyperedges") or [])
    seen_h = {item.get("id") for item in hypers if isinstance(item, dict)}
    for hyper in semantic.get("hyperedges") or []:
        hid = hyper.get("id")
        if hid and hid not in seen_h:
            hypers.append(hyper)
            seen_h.add(hid)
    graph.graph["hyperedges"] = hypers
    return graph


def _write_merged(root: Path, semantic: dict[str, Any], force: bool) -> bool:
    """Add a semantic layer onto the existing AST graph.json (additive)."""
    from graphify.cluster import cluster
    from graphify.export import to_json
    from graphify.paths import load_node_link_graph

    if not (semantic.get("nodes") or semantic.get("edges") or semantic.get("hyperedges")):
        print("semantic payload empty — AST graph unchanged")
        return True

    graph_path = _ensure_ast_graph(root)
    graph = load_node_link_graph(graph_path)
    graph = _add_semantic_layer(graph, semantic)
    communities = cluster(graph)
    wrote = to_json(graph, communities, str(graph_path), force=force)
    if not wrote:
        print(
            "error: to_json refused to write (shrink-guard). Pass --force to override.",
            file=sys.stderr,
        )
        return False
    inferred = sum(
        1 for _, _, data in graph.edges(data=True) if data.get("confidence") == "INFERRED"
    )
    print(
        f"semantic-merge: {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges, "
        f"{inferred} INFERRED"
    )
    return True


def cmd_prepare(root: Path, spec: Path, quiet_if_clean: bool) -> int:
    from graphify.cache import check_semantic_cache

    out = _out(root)
    paths, skipped_pointers, _detect = _semantic_paths(root)
    (out / ".graphify_root").write_text(str(root.resolve()), encoding="utf-8")

    if not spec.is_file():
        print(f"error: extraction spec not found: {spec}", file=sys.stderr)
        return 2

    skipped = _cache_skipped_pointers(root, spec, skipped_pointers)
    if skipped and not quiet_if_clean:
        print(f"semantic-prepare: cached {skipped} pointer file(s) as skip")

    cached_nodes, cached_edges, cached_hyper, uncached = check_semantic_cache(
        paths, root=root, prompt_file=spec
    )
    uncached_rel = [_rel(root, Path(p)) for p in uncached]
    (out / UNCACHED_NAME).write_text("\n".join(uncached_rel) + ("\n" if uncached_rel else ""), encoding="utf-8")
    cached_payload = {
        "nodes": cached_nodes,
        "edges": cached_edges,
        "hyperedges": cached_hyper,
    }
    (out / CACHED_NAME).write_text(
        json.dumps(cached_payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    _write_target_labels(root)
    hits = len(paths) - len(uncached)
    if not uncached:
        if not quiet_if_clean:
            print(f"semantic-prepare: {hits} cached, 0 uncached — skip builder")
        return 0
    print(f"semantic-prepare: {hits} cached, {len(uncached)} uncached")
    print("Load skill graphify-builder. Uncached files:")
    for rel in uncached_rel:
        print(f"  {rel}")
    return 0


def _clear_needs_update(root: Path) -> None:
    flag = _out(root) / NEEDS_UPDATE
    if flag.exists():
        flag.unlink()
        print("cleared graphify-out/needs_update")


def cmd_merge(root: Path, spec: Path, force: bool, from_cache: bool) -> int:
    from graphify.cache import check_semantic_cache, save_semantic_cache

    out = _out(root)
    paths, skipped_pointers, _detect_result = _semantic_paths(root)
    if spec.is_file() and skipped_pointers:
        _cache_skipped_pointers(root, spec, skipped_pointers)
    new = _load_agent_semantic(out)
    if not from_cache and not _payload_nonempty(new):
        print(
            "error: no semantic payload. Write graphify-out/.graphify_semantic.json "
            "or .graphify_chunk_*.json via skill graphify-builder, or use "
            "rehydrate/--from-cache.",
            file=sys.stderr,
        )
        return 2

    cached_nodes, cached_edges, cached_hyper, _uncached = check_semantic_cache(
        paths, root=root, prompt_file=spec if spec.is_file() else None
    )
    cached = {"nodes": cached_nodes, "edges": cached_edges, "hyperedges": cached_hyper}
    semantic = _combine(cached, new)

    if spec.is_file() and _payload_nonempty(new):
        saved = save_semantic_cache(
            new.get("nodes") or [],
            new.get("edges") or [],
            new.get("hyperedges") or [],
            root=root,
            prompt_file=spec,
        )
        print(f"semantic cache: saved {saved} file group(s)")

    if not _write_merged(root, semantic, force=force):
        return 1
    for chunk in out.glob(CHUNK_GLOB):
        try:
            chunk.unlink()
        except OSError:
            pass
    _clear_needs_update(root)
    return 0


def cmd_rehydrate(root: Path, spec: Path, force: bool) -> int:
    from graphify.cache import check_semantic_cache

    paths, _skipped_pointers, _detect_result = _semantic_paths(root)
    if not paths:
        print("semantic-rehydrate: no docs/images — AST graph unchanged")
        return 0

    graph_path = _out(root) / "graph.json"
    if not graph_path.is_file():
        print("semantic-rehydrate: no graph.json — skip")
        return 0

    cached_nodes, cached_edges, cached_hyper, uncached = check_semantic_cache(
        paths, root=root, prompt_file=spec if spec.is_file() else None
    )
    if not (cached_nodes or cached_edges or cached_hyper):
        print("semantic-rehydrate: cache empty — AST graph unchanged")
        return 0

    cached = {"nodes": cached_nodes, "edges": cached_edges, "hyperedges": cached_hyper}
    if not _write_merged(root, cached, force=force):
        return 1
    if uncached:
        print(f"semantic-rehydrate: {len(uncached)} file(s) still uncached — load graphify-builder")
    else:
        _clear_needs_update(root)
    return 0


def cmd_status(root: Path, spec: Path) -> int:
    from graphify.cache import check_semantic_cache

    paths, _skipped, _detect = _semantic_paths(root)
    uncached: list[str] = list(paths)
    if spec.is_file():
        _cn, _ce, _ch, uncached = check_semantic_cache(
            paths, root=root, prompt_file=spec
        )
    cached = len(paths) - len(uncached)
    graph_path = _out(root) / "graph.json"
    inferred = 0
    edges = 0
    if graph_path.is_file():
        try:
            data = json.loads(graph_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            data = {}
        links = data.get("links") or data.get("edges") or []
        edges = len(links)
        inferred = sum(
            1 for edge in links
            if isinstance(edge, dict) and edge.get("confidence") == "INFERRED"
        )
    pct = (inferred / edges * 100) if edges else 0.0
    print(f"semantic-status: {cached} cached, {len(uncached)} uncached")
    print(f"graph: {inferred} INFERRED / {edges} edges ({pct:.0f}%)")
    return 0


def cmd_write_json(root: Path, input_data: str | None = None, chunk_id: str | None = None) -> int:
    """Safely write semantic extraction JSON to graphify-out/.graphify_semantic.json
    or .graphify_chunk_<chunk_id>.json without needing write_to_file."""
    out_dir = _out(root)
    if input_data is None:
        raw = sys.stdin.read()
    else:
        raw = input_data
    if not raw.strip():
        print("write-json: empty input", file=sys.stderr)
        return 1
    try:
        data = json.loads(raw.lstrip("\ufeff"))
    except json.JSONDecodeError as err:
        print(f"write-json: invalid JSON: {err}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print("write-json: root must be a JSON object", file=sys.stderr)
        return 1
    if chunk_id:
        target = out_dir / f".graphify_chunk_{chunk_id}.json"
    else:
        target = out_dir / SEMANTIC_NAME
    target.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"write-json: wrote {len(data.get('nodes', []))} node(s), {len(data.get('edges', []))} edge(s) -> {target.name}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "merge", "rehydrate", "status", "write-json"))
    parser.add_argument("--root", type=Path, default=Path("."), help="project root")
    parser.add_argument("--spec", type=Path, default=None, help="extraction-spec.md path")
    parser.add_argument("--force", action="store_true", help="bypass to_json shrink-guard")
    parser.add_argument("--from-cache", action="store_true", help="merge even without new JSON")
    parser.add_argument(
        "--quiet-if-clean",
        action="store_true",
        help="prepare: print nothing when uncached count is 0",
    )
    parser.add_argument("--data", type=str, default=None, help="write-json: JSON string payload")
    parser.add_argument("--chunk", type=str, default=None, help="write-json: chunk identifier")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    spec = _spec_path(str(args.spec) if args.spec else None, root)

    if args.command == "prepare":
        return cmd_prepare(root, spec, args.quiet_if_clean)
    if args.command == "merge":
        return cmd_merge(root, spec, args.force, args.from_cache)
    if args.command == "status":
        return cmd_status(root, spec)
    if args.command == "write-json":
        return cmd_write_json(root, args.data, args.chunk)
    return cmd_rehydrate(root, spec, args.force)


if __name__ == "__main__":
    sys.exit(main())
