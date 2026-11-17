#!/usr/bin/env bash
# link-agents: give Claude Code the host's shared skills and prompts.
#
# ~/.agents is the host's dotfiles agents/ directory, bind-mounted read-only.
# Codex and prime-agent read ~/.agents/skills on their own, and prime reads
# ~/.agents/prompts through the bound settings.json. Claude Code reads only
# ~/.claude (a per-container volume), so each shared skill and prompt gets a
# link there. Runs on every container start: entries added on the host since
# show up after a restart, and links to removed ones are dropped.
set -euo pipefail

agents="$HOME/.agents"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$claude/skills" "$claude/commands"

# Links to skills or prompts that were deleted on the host
for link in "$claude"/skills/* "$claude"/commands/*; do
    [[ -L "$link" && ! -e "$link" ]] || continue
    [[ "$(readlink "$link")" == "$agents/"* ]] || continue
    rm "$link"
done

# reference/ and review-patterns.md aren't skills, but skills read them through
# ../ paths, so they're linked too. synced/ is where Claude Code downloads
# claude.ai account skills: it must stay writable, so the host's is skipped.
for entry in "$agents"/skills/*; do
    [[ -e "$entry" ]] || continue
    name="${entry##*/}"
    [[ "$name" != synced ]] || continue
    dst="$claude/skills/$name"
    [[ -L "$dst" || ! -e "$dst" ]] || continue
    ln -sfn "$entry" "$dst"
done

for prompt in "$agents"/prompts/*.md; do
    [[ -f "$prompt" ]] || continue
    name="${prompt##*/}"
    case "$name" in
        # Instructions for agents editing the prompts, not prompts themselves
        AGENTS.md|CLAUDE.md) continue ;;
    esac
    dst="$claude/commands/$name"
    [[ -L "$dst" || ! -e "$dst" ]] || continue
    ln -sfn "$prompt" "$dst"
done

# A same-named link in codex's or prime's own skills directory would load the
# skill twice. Containers created before this script linked grev's deb copy there.
for dir in "$HOME/.codex/skills" "$HOME/.prime/agent/skills"; do
    for link in "$dir"/*; do
        [[ -L "$link" && -e "$agents/skills/${link##*/}" ]] || continue
        rm "$link"
    done
done
