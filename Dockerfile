# ============================================================================
# ByteBot Standard Image - Public Desktop + Standard ByteBot
# ============================================================================
# Purpose: Combined desktop environment + standard bytebotd (no computer-control)
# Privacy: PUBLIC (contains no proprietary code)
# Build: GitHub Actions (weekly or on-demand)
# Build time: ~18 minutes
# ============================================================================

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0
ENV TZ=America/Los_Angeles

# ============================================================================
# 1. System dependencies and desktop environment (~5 min)
# ============================================================================
RUN apt-get update && apt-get install -y \
    # X11 / VNC / Desktop
    xvfb x11vnc xauth x11-xserver-utils x11-apps \
    xfce4 xfce4-goodies dbus wmctrl lightdm \
    sudo software-properties-common \
    # Development tools
    python3 python3-pip curl wget git vim \
    # Utilities
    supervisor netcat-openbsd \
    # Applications
    xpdf gedit xpaint \
    # Build dependencies (for bytebotd compilation)
    libxtst-dev cmake libx11-dev libxinerama-dev \
    libxi-dev libxt-dev libxrandr-dev libxkbcommon-dev \
    libxkbcommon-x11-dev xclip build-essential \
    # Remove unneeded
    && apt-get remove -y light-locker xfce4-screensaver xfce4-power-manager || true \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Setup dbus
RUN mkdir -p /run/dbus && dbus-uuidgen --ensure=/etc/machine-id

# ============================================================================
# 2. Install Applications (~8 min)
# ============================================================================

# Firefox and Thunderbird
RUN apt-get update && apt-get install -y \
    software-properties-common apt-transport-https wget gnupg \
    mesa-utils libgl1-mesa-dri libgl1-mesa-glx libcap2-bin \
    fontconfig fonts-dejavu fonts-liberation fonts-freefont-ttf \
    && add-apt-repository -y ppa:mozillateam/ppa \
    && apt-get update \
    && apt-get install -y firefox-esr thunderbird \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/firefox-esr 200 \
    && update-alternatives --set x-www-browser /usr/bin/firefox-esr \
    && fc-cache -f -v

# 1Password (architecture-specific)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg && \
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | \
        tee /etc/apt/sources.list.d/1password.list && \
        mkdir -p /etc/debsig/policies/AC2D62742012EA22/ && \
        curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
        tee /etc/debsig/policies/AC2D62742012EA22/1password.pol && \
        mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 && \
        curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg && \
        apt-get update && apt-get install -y 1password && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# VSCode (architecture-specific)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        apt-get update && apt-get install -y wget gpg apt-transport-https \
        software-properties-common && \
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor -o /usr/share/keyrings/ms_vscode.gpg && \
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/ms_vscode.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list && \
        apt-get update && apt-get install -y code && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ============================================================================
# 3. Install Node.js (~1 min)
# ============================================================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================================
# 4. noVNC and websockify (~1 min)
# ============================================================================
RUN pip3 install --upgrade pip && \
    git clone https://github.com/novnc/noVNC.git /opt/noVNC && \
    git clone https://github.com/novnc/websockify.git /opt/websockify && \
    cd /opt/websockify && pip3 install .

# ============================================================================
# 5. User setup
# ============================================================================
RUN useradd -ms /bin/bash user && \
    echo "user:user" | chpasswd && \
    usermod -aG sudo user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /var/run/dbus && chmod 755 /var/run/dbus && \
    chown user:user /var/run/dbus

RUN mkdir -p /tmp/bytebot-screenshots && \
    chown -R user:user /tmp/bytebot-screenshots

RUN mkdir -p /home/user/Desktop /home/user/.config /home/user/.local/share /home/user/.cache && \
    chown -R user:user /home/user

# ============================================================================
# 6. Copy and Build Standard ByteBot (NO computer-control) (~5 min)
# ============================================================================

# Note: GitHub Actions will clone bytebot-agent-desktop repo and copy files
# excluding the computer-control directory before building this image

# Copy shared packages
COPY packages/shared/ /bytebot/shared/

# Copy bytebotd (computer-control will be excluded via .dockerignore)
COPY packages/bytebotd/package.json /bytebot/bytebotd/
COPY packages/bytebotd/tsconfig.json /bytebot/bytebotd/
COPY packages/bytebotd/src/ /bytebot/bytebotd/src/

# Remove computer-control if it was copied (belt and suspenders)
RUN rm -rf /bytebot/bytebotd/src/computer-control

WORKDIR /bytebot/bytebotd

# Install dependencies (~3 min)
RUN npm install --build-from-source
RUN npm rebuild uiohook-napi --build-from-source

# Build TypeScript (~1 min)
RUN npm run build || echo "Build may fail without computer-control, that's expected"

# Build custom libnut (~2 min)
WORKDIR /compile
RUN git clone https://github.com/ZachJW34/libnut-core.git && \
    cd libnut-core && \
    npm install && \
    npm run build:release

RUN rm -f /bytebot/bytebotd/node_modules/@nut-tree-fork/libnut-linux/build/Release/libnut.node && \
    cp /compile/libnut-core/build/Release/libnut.node \
       /bytebot/bytebotd/node_modules/@nut-tree-fork/libnut-linux/build/Release/libnut.node

# Clean up
RUN rm -rf /compile

# Copy system configuration files (supervisord, lightdm, etc.)
# Note: GitHub Actions creates at least an empty root/ directory
COPY root/ /

RUN chown -R user:user /home/user

# ============================================================================
# 7. Metadata
# ============================================================================
LABEL org.opencontainers.image.title="ByteBot Standard Image"
LABEL org.opencontainers.image.description="Desktop environment + standard bytebotd (no computer-control)"
LABEL org.opencontainers.image.source="https://github.com/elsa17z/bytebot-standard"
LABEL org.opencontainers.image.licenses="MIT"
LABEL bytebot.layer="standard"
LABEL bytebot.version="2.0"

WORKDIR /bytebot/bytebotd

# Base image - doesn't run by itself (needs computer-control to be added)
CMD ["/bin/bash"]
