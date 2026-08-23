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

# --- Aliases (Modern Rust/Go CLI replacements) ---
alias cat = bat --paging=never
alias ls = eza --icons --group-directories-first
alias ll = eza -l --icons --git --group-directories-first
alias la = eza -la --icons --git --group-directories-first
alias tree = eza --tree --icons
alias lg = lazygit
alias btm = bottom
alias grep = rg
alias find = fd
alias df = duf
alias du = dust
