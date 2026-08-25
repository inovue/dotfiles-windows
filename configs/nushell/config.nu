# Nushell User Configuration ($nu.config-path)

$env.config = {
    show_banner: false
    table: {
        mode: rounded
        index_mode: always
        show_empty: true
        padding: { left: 1, right: 1 }
    }
    completions: {
        case_sensitive: false
        quick: true
        partial: true
        algorithm: "fuzzy"
    }
    history: {
        max_size: 100_000
        sync_on_enter: true
        file_format: "plaintext"
    }
    cursor_shape: {
        emacs: line
        vi_insert: line
        vi_normal: block
    }
}

# --- Aliases (Modern Rust/Go CLI replacements & Ultra-fast defaults) ---
alias cat = bat --paging=never
alias ls = eza --icons --group-directories-first
alias ll = eza -l --icons --git --group-directories-first
alias la = eza -la --icons --git --group-directories-first
alias tree = eza --tree --icons
alias lg = lazygit
alias btm = bottom
alias grep = rg
alias find = fd
alias sed = sd
alias sg = ast-grep
alias df = duf
alias du = dust
alias hk = hunk
alias hx = helix
alias dft = difft
alias http = xh
alias ps = procs
alias hex = hexyl
alias md = glow

# --- Mermaid Terminal Rendering (Cognitive Load Reduction) ---
# Render Mermaid diagrams directly in terminal or lightweight popup
def mm [
    path?: string   # Optional file path to render
    --img (-i)      # Render as inline graphic in terminal (via Kroki + Chafa)
    --web (-w)      # Render in ultra-fast Edge App Mode popup
    --compact (-c)  # Force ultra-compact ASCII mode
] {
    let raw_text = if ($path != null and ($path | path exists)) {
        open $path
    } else {
        $in | default (try { powershell -NoProfile -NonInteractive -Command "Get-Clipboard" | str trim } catch { "" })
    }

    # Automatically extract ```mermaid ... ``` block if wrapped in markdown
    let mmd = if ($raw_text | str contains "```mermaid") {
        $raw_text | split row "```mermaid" | get 1 | split row "```" | get 0 | str trim
    } else if ($raw_text | str contains "```") {
        $raw_text | split row "```" | get 1 | split row "```" | get 0 | str trim
    } else {
        $raw_text
    }

    if ($mmd | is-empty) {
        print "No Mermaid diagram content found in input or clipboard."
        return
    }

    # Helper: Open in Default Browser
    let open_web = {|content|
        let tmp_html = $"($env.TEMP)/mermaid_preview.html" | path expand
        let template = "<!DOCTYPE html>
<html>
<head>
  <meta charset='utf-8'>
  <title>Mermaid Diagram Preview</title>
  <script src='https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js'></script>
  <style>
    body { background: #1e1e2e; color: #cdd6f4; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 32px; display: flex; justify-content: center; align-items: center; min-height: 90vh; }
    .mermaid { background: #181825; padding: 32px; border-radius: 16px; box-shadow: 0 8px 32px rgba(0,0,0,0.4); border: 1px solid #313244; max-width: 95vw; overflow: auto; }
  </style>
</head>
<body>
  <div class='mermaid'>
__MERMAID_CONTENT__
  </div>
  <script>mermaid.initialize({startOnLoad: true, theme: 'dark', securityLevel: 'strict'});</script>
</body>
</html>"
        $template | str replace "__MERMAID_CONTENT__" $content | save -f $tmp_html

        # Open in system default browser
        ^cmd /c start "" ($tmp_html | str replace -a "/" "\\")
    }

    if $web {
        do $open_web $mmd
        return
    }

    # Detect diagram type (Flowcharts vs. Sequence/ER/State/Class/Git)
    let non_empty = ($mmd | lines | each {|l| $l | str trim } | where {|l| ($l | is-not-empty) and (not ($l | str starts-with "%%")) })
    let first_line = if ($non_empty | is-empty) { "" } else { $non_empty | first }
    let is_flowchart = (($first_line | str starts-with "graph") or ($first_line | str starts-with "flowchart"))

    # If --img is explicitly requested, render via Kroki + Chafa (with 3s timeout)
    if $img {
        let tmp_png = $"($env.TEMP)/mermaid_render.png"
        let res = (do { $mmd | ^curl.exe -s --connect-timeout 2 --max-time 3 -X POST https://kroki.io/mermaid/png -H "Content-Type: text/plain" --data-binary @- -o $tmp_png } | complete)
        if ($tmp_png | path exists) and $res.exit_code == 0 {
            if (which chafa | is-not-empty) {
                ^chafa $tmp_png
                return
            }
        }
    }

    # If diagram is non-flowchart (Sequence, ER, State, Class, Git, etc.), open high-res Web popup
    if (not $is_flowchart) {
        print $"[Mermaid] Opening high-resolution preview for '($first_line)'..."
        do $open_web $mmd
        return
    }

    # Adaptive ASCII Text Mode for Flowcharts
    let term_cols = (term size | get columns)
    let pad_x = if ($compact or $term_cols < 100) { "1" } else if $term_cols < 140 { "2" } else { "3" }
    let pad_y = if ($compact or $term_cols < 100) { "1" } else { "1" }
    let border_p = if ($compact or $term_cols < 100) { "0" } else { "1" }

    if (which mermaid-ascii | is-not-empty) {
        $mmd | ^mermaid-ascii -x $pad_x -y $pad_y -p $border_p
    } else if (which bunx | is-not-empty) {
        $mmd | ^bunx --bun mermaid-ascii -x $pad_x -y $pad_y -p $border_p
    } else if (which npx | is-not-empty) {
        $mmd | ^npx -y mermaid-ascii -x $pad_x -y $pad_y -p $border_p
    }
}
