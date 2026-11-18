# Claude Code Devcontainer
# Based on Microsoft devcontainer image for better devcontainer integration
FROM ghcr.io/astral-sh/uv:0.10@sha256:10902f58a1606787602f303954cea099626a4adb02acbac4c69920fe9d278f82 AS uv
FROM mcr.microsoft.com/devcontainers/base:ubuntu24.04@sha256:4bcb1b466771b1ba1ea110e2a27daea2f6093f9527fb75ee59703ec89b5561cb

ARG TZ
ENV TZ="$TZ"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install additional system packages (base image already includes git, curl, sudo, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
  # Sandboxing support for Claude Code
  bubblewrap \
  socat \
  # Modern CLI tools
  fish \
  fd-find \
  ripgrep \
  tmux \
  # Build tools
  build-essential \
  # Utilities
  jq \
  nano \
  unzip \
  vim \
  # Network tools (for security testing)
  dnsutils \
  ipset \
  iptables \
  iproute2 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install git-delta
# renovate: datasource=github-releases depName=dandavison/delta
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" -o /tmp/git-delta.deb && \
  dpkg -i /tmp/git-delta.deb && \
  rm /tmp/git-delta.deb

# Install the grev tools: grep/isv/rank/tagv/seek and friends, where the pattern is a
# plain-English question a model answers instead of a regex. They let an agent screen inputs
# far larger than its context for fractions of a cent, and print the input back verbatim.
#
# The deb is used rather than `go install` because it also lands the man pages and the shell
# completions. Its copy of the agent skill (/usr/share/grev/skills/grev) goes unused: agents
# here read the host's vendored copy from the ~/.agents mount, like every other shared skill.
# It declares no dependencies, so plain dpkg -i needs no apt resolution. checksums.txt is
# verified before install: these are ~40MB of prebuilt third-party binaries.
# renovate: datasource=github-releases depName=aurorainfra/grev
ARG GREV_VERSION=0.4.0
RUN ARCH=$(dpkg --print-architecture) && \
  DEB="grev_${GREV_VERSION}_${ARCH}.deb" && \
  REL="https://github.com/aurorainfra/grev/releases/download/v${GREV_VERSION}" && \
  cd /tmp && \
  curl -fsSL -O "${REL}/${DEB}" && \
  curl -fsSL -O "${REL}/checksums.txt" && \
  sha256sum --ignore-missing -c checksums.txt && \
  dpkg -i "${DEB}" && \
  rm -f "${DEB}" checksums.txt

# Install uv (Python package manager) via multi-stage copy
COPY --from=uv /uv /usr/local/bin/uv

# Install fzf from GitHub releases (newer than apt, includes built-in shell integration)
# renovate: datasource=github-releases depName=junegunn/fzf
ARG FZF_VERSION=0.70.0
RUN ARCH=$(dpkg --print-architecture) && \
  case "${ARCH}" in \
    amd64) FZF_ARCH="linux_amd64" ;; \
    arm64) FZF_ARCH="linux_arm64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
  esac && \
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${FZF_ARCH}.tar.gz" | tar -xz -C /usr/local/bin

# Install Go toolchain
# renovate: datasource=golang-version depName=go
ARG GO_VERSION=1.24.3
RUN ARCH=$(dpkg --print-architecture) && \
  case "${ARCH}" in \
    amd64) GO_ARCH="linux-amd64" ;; \
    arm64) GO_ARCH="linux-arm64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
  esac && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.${GO_ARCH}.tar.gz" | tar -xz -C /usr/local

# Create directories and set ownership (combined for fewer layers)
RUN mkdir -p /commandhistory /workspace /home/vscode/.claude /home/vscode/.codex /opt /home/vscode/.config/fish && \
  touch /commandhistory/.bash_history && \
  touch /commandhistory/.zsh_history && \
  chown -R vscode:vscode /commandhistory /workspace /home/vscode/.claude /home/vscode/.codex /opt /home/vscode/.config/fish

# Set environment variables
ENV DEVCONTAINER=true
ENV SHELL=/usr/bin/fish
ENV EDITOR=vim
ENV VISUAL=vim

RUN chsh -s /usr/bin/fish vscode
# Go and Rust environment
ENV GOPATH="/home/vscode/go"
ENV CARGO_HOME="/home/vscode/.cargo"
ENV RUSTUP_HOME="/home/vscode/.rustup"

WORKDIR /workspace

# Switch to non-root user for remaining setup
USER vscode

# Set PATH so Go, Cargo, and user-installed binaries are available
ENV PATH="/usr/local/go/bin:${GOPATH}/bin:${CARGO_HOME}/bin:/home/vscode/.local/bin:$PATH"

# Install Claude Code natively with marketplace plugins
RUN curl -fsSL https://claude.ai/install.sh | bash && \
  claude plugin marketplace add anthropics/skills && \
  claude plugin marketplace add trailofbits/skills && \
  claude plugin marketplace add trailofbits/skills-curated && \
  claude plugin marketplace add 6m1w/claude-sound-fx && \
  claude plugin install sound-fx@claude-sound-fx

# Install Python 3.13 via uv (fast binary download, not source compilation)
RUN uv python install 3.13 --default

# Install ast-grep (AST-based code search)
RUN uv tool install ast-grep-cli

# Install nvm and Node.js
# renovate: datasource=github-releases depName=nvm-sh/nvm
ARG NVM_VERSION=0.40.3
ARG NODE_VERSION=22
ENV NVM_DIR="/home/vscode/.nvm"
RUN curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash && \
  . "$NVM_DIR/nvm.sh" && \
  nvm install ${NODE_VERSION} && \
  nvm alias default ${NODE_VERSION} && \
  ln -sfn "$NVM_DIR/versions/node/$(nvm version default)" "$NVM_DIR/current"

# nvm installs node under a version-stamped path and only puts it on PATH from `nvm.sh`,
# which the default fish shell never sources — so node was reachable in zsh and nowhere else.
# $NVM_DIR/current is a stable symlink to the default install, letting PATH reach node without
# nvm. Codex depends on this: the `codex` npm bin is a `#!/usr/bin/env node` shim that execs
# the platform binary, so a PATH without node makes `codex` fail at exec, not at import.
ENV PATH="${NVM_DIR}/current/bin:${PATH}"

# Install Codex CLI. Global npm installs land in $NVM_DIR/current/bin, so this needs no
# further PATH wiring. ~/.codex is a per-container volume holding the login: nothing is bound
# from the host, so credentials never cross the container boundary — run `codex login` once
# per container and the volume carries it across restarts and rebuilds.
# renovate: datasource=npm depName=@openai/codex
ARG CODEX_VERSION=0.153.4
RUN npm install -g "@openai/codex@${CODEX_VERSION}"

# Codex's default reasoning effort. The host's codex/config.toml is never mounted (it is
# macOS-only), so it lives in the system config layer instead. ~/.codex/config.toml in the
# volume still overrides it, e.g. when /model saves a different effort.
RUN sudo mkdir -p /etc/codex && \
  printf 'model_reasoning_effort = "xhigh"\n' | sudo tee /etc/codex/config.toml >/dev/null

# Install prime-agent (the Rust build). The release archive is checked against a checksum
# pinned here, then installed by the installer bundled inside it (`--archive`). Never pipe the
# live install.sh: that URL serves whatever installer is current, and when upstream swapped it
# for the Rust one it could no longer install the version pinned here, which broke the build.
# To bump, copy both checksums from the new release's SHA256SUMS (same URL as the archive,
# with SHA256SUMS as the file name). renovate has no datasource for this channel. See
# ~/repos/dotfiles/docs/decisions/2026-11-17-prime-agent-installs-from-a-pinned-archive.md
#
# ~/.prime is a per-container volume at runtime — only the config JSONs are bound from the
# host, because prime's daemon, session and lease state cannot be shared between containers
# without them claiming each other's sessions. The launcher (~/.local/bin) and payload
# (~/.local/share/prime-agent) live in the image instead. PRIME_AGENT_CODING_AGENT_DIR keeps
# the build-time bootstrap's writes out of ~/.prime (a fresh volume would copy them in), and
# PRIME_AGENT_KERNEL_VENV pins the IPython kernel venv into /opt/prime, where one image-baked
# copy serves every container instead of each paying a ~270MB uv bootstrap on first ipython
# use. The installer's kernel pre-warm is best-effort, so the build checks the venv exists.
ARG PRIME_AGENT_VERSION=0.10.3
ENV PRIME_AGENT_KERNEL_VENV=/opt/prime/kernel-venv
RUN case "${PRIME_AGENT_VERSION}-$(dpkg --print-architecture)" in \
    0.10.3-amd64) PLATFORM=linux-x64 SHA256=811d9f0ec9dff007d5bda9c8435b0e7f46ef7041fa2fc103efc9edc295cb5528 ;; \
    0.10.3-arm64) PLATFORM=linux-arm64 SHA256=a41da67f91897bc32a630fac65cc141bf83e1f2cb91ec133ef9194e2e8a99926 ;; \
    *) echo "No pinned checksum for prime-agent ${PRIME_AGENT_VERSION} on $(dpkg --print-architecture); add it from that release's SHA256SUMS" && exit 1 ;; \
  esac && \
  ARCHIVE="prime-agent-${PRIME_AGENT_VERSION}-${PLATFORM}.tar.gz" && \
  mkdir -p /opt/prime/agent /tmp/prime-agent && \
  cd /tmp/prime-agent && \
  curl -fsSLO "https://pub-728493de92a943e2a9b2d17b4719f318.r2.dev/releases/v${PRIME_AGENT_VERSION}/${ARCHIVE}" && \
  echo "${SHA256}  ${ARCHIVE}" | sha256sum -c - && \
  tar -xzf "${ARCHIVE}" install.sh && \
  PRIME_AGENT_CODING_AGENT_DIR=/opt/prime/agent sh install.sh --archive "/tmp/prime-agent/${ARCHIVE}" && \
  test -x "${PRIME_AGENT_KERNEL_VENV}/bin/python" && \
  cd / && rm -rf /tmp/prime-agent

# Install Fisher (fish plugin manager) and plugins
RUN fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher jorgebucaran/nvm.fish'

# Copy zsh configuration
COPY --chown=vscode:vscode .zshrc /home/vscode/.zshrc.custom

# set a better term var for some command handling
ENV TERM=xterm-256color

# Append custom zshrc to the main one
RUN echo 'source ~/.zshrc.custom' >> /home/vscode/.zshrc

# Copy fish configuration
COPY --chown=vscode:vscode config.fish /home/vscode/.config/fish/config.fish

# Copy post_install script
COPY --chown=vscode:vscode post_install.py /opt/post_install.py

# Links the host's shared skills and prompts (~/.agents mount) into Claude's config volume
# on every container start. Root-owned so nothing in the container can rewrite it.
COPY link-agents.sh /usr/local/bin/link-agents
