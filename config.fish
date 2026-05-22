# Fish shell configuration for Claude Code devcontainer

# Claude Code and user-installed binaries
fish_add_path $HOME/.local/bin

# Go toolchain
set -gx GOPATH $HOME/go
fish_add_path /usr/local/go/bin $GOPATH/bin

# Rust toolchain
fish_add_path $HOME/.cargo/bin

# History
set -gx HISTFILE /commandhistory/fish_history

# Aliases
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias fd=fdfind
alias sg=ast-grep
alias grep='grep --color=auto'
alias claude-yolo='claude --dangerously-skip-permissions'

# fzf configuration
set -gx FZF_DEFAULT_COMMAND 'fdfind --type f --hidden --follow --exclude .git'
set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
set -gx FZF_ALT_C_COMMAND 'fdfind --type d --hidden --follow --exclude .git'
set -gx FZF_DEFAULT_OPTS '--height 40% --layout=reverse --border --info=inline'

# Auto-start audio relay shim if not running
if not pgrep -f "socat.*19876" >/dev/null 2>&1
    setsid socat TCP-LISTEN:19876,fork,reuseaddr,bind=127.0.0.1 TCP:172.17.0.1:19876 >/dev/null 2>&1 &
end
