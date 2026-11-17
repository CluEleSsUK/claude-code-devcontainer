#!/usr/bin/env bash
# link-agents: give Claude Code the host's shared skills.
#
# ~/.agents is the host's dotfiles agents/ directory, bind-mounted read-only.
# Codex and prime-agent read ~/.agents/skills on their own. Claude Code reads
# only ~/.claude (a per-container volume), so each shared skill gets a link
# there. Runs on every container start: skills added on the host since show up
# after a restart, and links to removed ones are dropped.
set -euo pipefail

agents="$HOME/.agents"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$claude/skills"

# Links to entries deleted on the host. commands/ held links to the prompts
# before they became skills, so volumes from that version still have them.
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

# A same-named link in codex's or prime's own skills directory would load the
# skill twice. Containers created before this script linked grev's deb copy there.
for dir in "$HOME/.codex/skills" "$HOME/.prime/agent/skills"; do
    for link in "$dir"/*; do
        [[ -L "$link" && -e "$agents/skills/${link##*/}" ]] || continue
        rm "$link"
    done
done
