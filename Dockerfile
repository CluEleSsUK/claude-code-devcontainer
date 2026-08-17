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
  fd-find \
  fish \
  ripgrep \
  tmux \
  zsh \
  fish \
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
RUN mkdir -p /commandhistory /workspace /home/vscode/.claude /opt /home/vscode/.config/fish && \
  touch /commandhistory/.bash_history && \
  touch /commandhistory/.zsh_history && \
  chown -R vscode:vscode /commandhistory /workspace /home/vscode/.claude /opt /home/vscode/.config/fish

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
  npm install -g @openai/codex

# Install prime-agent. Not on the public npm registry: the vendor installer resolves a
# pinned release and verifies it against a SHA256SUMS manifest. Bump the version by hand —
# renovate has no datasource for this channel.
#
# ~/.prime is bind-mounted from the macOS host at runtime, so prime-agent's components must
# not live under it: the host's builds are Mach-O and cannot execute here, and anything the
# image installs there is shadowed anyway. PRIME_AGENT_CODING_AGENT_DIR redirects the
# build-time bootstrap and PRIME_AGENT_KERNEL_VENV pins the Python 3.11 IPython kernel venv
# into /opt/prime, leaving auth/models/settings/sessions to come from the bind mount at
# runtime. fd/rg need no baking — the bootstrap reuses the apt copies, and at runtime
# prime-agent rejects the host's macOS ones (they fail its --version probe) for /usr/bin.
ARG PRIME_AGENT_VERSION=0.7.2
ENV PRIME_AGENT_KERNEL_VENV=/opt/prime/kernel-venv
RUN mkdir -p /opt/prime/agent && \
  . "$NVM_DIR/nvm.sh" && \
  PRIME_AGENT_VERSION="${PRIME_AGENT_VERSION}" \
  PRIME_AGENT_CODING_AGENT_DIR=/opt/prime/agent \
  PRIME_AGENT_BOOTSTRAP_KERNEL_ON_INSTALL=1 \
  PRIME_AGENT_INSTALLER_PLAIN=1 \
  bash -c 'curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | sh'

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

# Install Oh My Zsh
# renovate: datasource=github-releases depName=deluan/zsh-in-docker
ARG ZSH_IN_DOCKER_VERSION=1.2.1
RUN sh -c "$(curl -fsSL https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -x

# Install Fisher (fish plugin manager) and plugins
RUN fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher jorgebucaran/nvm.fish'

# Copy zsh configuration
COPY --chown=vscode:vscode .zshrc /home/vscode/.zshrc.custom

# Append custom zshrc to the main one
RUN echo 'source ~/.zshrc.custom' >> /home/vscode/.zshrc

# Copy fish configuration
COPY --chown=vscode:vscode config.fish /home/vscode/.config/fish/config.fish

# Copy post_install script
COPY --chown=vscode:vscode post_install.py /opt/post_install.py
