#!/bin/bash
# lib/detect.sh — Dependency detection and installation for VoxFree
# Sourced by deps.sh. Provides detect_* and install_* functions.
#
# After sourcing, call:
#   detect_whisper   → sets $WHISPER_BIN, $WHISPER_VENV
#   install_whisper  → installs whisper-ctranslate2 to $TARGET_VENV
#   detect_mimic3    → sets $MIMIC3_BIN, $MIMIC3_METHOD
#   install_mimic3   → installs mimic3 via .deb or pip fallback

# Expects these variables to be set by the caller:
#   INSTALL_MODE   — "system" or "user"
#   ACTUAL_USER    — the non-root user to install for
#   ok/info/warn   — output functions from the parent script

# ── Whisper detection ─────────────────────────────────────────────────────────

detect_whisper() {
    WHISPER_BIN=""
    WHISPER_VENV=""

    # 1. System venv (standard VoxFree system install)
    if [ -f /opt/openai-whisper/bin/whisper-ctranslate2 ]; then
        WHISPER_BIN=/opt/openai-whisper/bin/whisper-ctranslate2
        WHISPER_VENV=/opt/openai-whisper
        return 0
    fi

    # 2. User venv (VoxFree --user install)
    if [ -n "${ACTUAL_USER:-}" ]; then
        local UH
        UH=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
        local CANDIDATE="$UH/.local/share/voxfree/whisper-venv"
        if [ -f "$CANDIDATE/bin/whisper-ctranslate2" ]; then
            WHISPER_BIN="$CANDIDATE/bin/whisper-ctranslate2"
            WHISPER_VENV="$CANDIDATE"
            return 0
        fi
    fi

    # 3. Any existing whisper in PATH (from another tool)
    if command -v whisper >/dev/null 2>&1; then
        local TARGET
        TARGET=$(readlink -f "$(which whisper)" 2>/dev/null)
        if echo "$TARGET" | grep -qE "whisper-ctranslate2|openai-whisper"; then
            WHISPER_BIN="$TARGET"
            warn "Using pre-existing whisper at $WHISPER_BIN"
            warn "For best performance, whisper-ctranslate2 is recommended"
            return 0
        fi
    fi

    return 1
}

install_whisper() {
    local LINK_PATH

    if [ "${INSTALL_MODE:-system}" = "system" ]; then
        TARGET_VENV="/opt/openai-whisper"
        LINK_PATH="/usr/local/bin/whisper"
    else
        local UH
        UH=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
        TARGET_VENV="$UH/.local/share/voxfree/whisper-venv"
        LINK_PATH="$UH/.local/bin/whisper"
        mkdir -p "$UH/.local/bin"
    fi

    info "Creating Python venv at $TARGET_VENV ..."
    python3 -m venv "$TARGET_VENV"
    "$TARGET_VENV/bin/pip" install --upgrade pip --quiet

    info "Installing whisper-ctranslate2 (no PyTorch, CTranslate2-based) ..."
    if "$TARGET_VENV/bin/pip" install whisper-ctranslate2 --quiet; then
        WHISPER_BIN="$TARGET_VENV/bin/whisper-ctranslate2"
    else
        warn "whisper-ctranslate2 failed — trying openai-whisper as fallback ..."
        "$TARGET_VENV/bin/pip" install openai-whisper --quiet
        WHISPER_BIN="$TARGET_VENV/bin/whisper"
    fi

    WHISPER_VENV="$TARGET_VENV"
    ln -sf "$WHISPER_BIN" "$LINK_PATH"

    if [ "${INSTALL_MODE:-system}" != "system" ] && [ -n "${ACTUAL_USER:-}" ]; then
        chown -R "$ACTUAL_USER:$ACTUAL_USER" "$TARGET_VENV" 2>/dev/null || true
        chown "$ACTUAL_USER:$ACTUAL_USER" "$LINK_PATH" 2>/dev/null || true
    fi

    ok "whisper installed → $LINK_PATH"
}

# ── Whisper model detection ───────────────────────────────────────────────────

detect_whisper_model() {
    HF_CACHE_DIR=""

    # Shared system cache (preferred)
    if [ -d "/var/cache/huggingface/hub/models--Systran--faster-whisper-base.en" ]; then
        HF_CACHE_DIR="/var/cache/huggingface"
        return 0
    fi

    # User cache
    if [ -n "${ACTUAL_USER:-}" ]; then
        local UH
        UH=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
        if [ -d "$UH/.cache/huggingface/hub/models--Systran--faster-whisper-base.en" ]; then
            HF_CACHE_DIR="$UH/.cache/huggingface"
            return 0
        fi
    fi

    # Current user fallback
    if [ -d "$HOME/.cache/huggingface/hub/models--Systran--faster-whisper-base.en" ]; then
        HF_CACHE_DIR="$HOME/.cache/huggingface"
        return 0
    fi

    return 1
}

install_whisper_model() {
    local CACHE_DIR MODEL_DIR

    if [ "${INSTALL_MODE:-system}" = "system" ]; then
        CACHE_DIR="/var/cache/huggingface"
    else
        local UH
        UH=$(getent passwd "${ACTUAL_USER:-$USER}" | cut -d: -f6)
        CACHE_DIR="$UH/.cache/huggingface"
    fi

    mkdir -p "$CACHE_DIR/hub"
    chmod 755 "$CACHE_DIR" "$CACHE_DIR/hub" 2>/dev/null || true

    MODEL_DIR="$CACHE_DIR/hub/models--Systran--faster-whisper-base.en"

    if [ -d "$MODEL_DIR" ]; then
        ok "Whisper base.en model already at $CACHE_DIR/"
        HF_CACHE_DIR="$CACHE_DIR"
        return 0
    fi

    # Copy from any user home cache to avoid re-download
    for UH in /home/*/; do
        local CAND="${UH}.cache/huggingface/hub/models--Systran--faster-whisper-base.en"
        if [ -d "$CAND" ]; then
            info "Found model in $CAND — copying to $CACHE_DIR/ ..."
            cp -r "$CAND" "$CACHE_DIR/hub/"
            chmod -R a+rX "$CACHE_DIR" 2>/dev/null || true
            ok "Model copied to $CACHE_DIR/"
            HF_CACHE_DIR="$CACHE_DIR"
            return 0
        fi
    done

    # Download
    info "Downloading Whisper base.en (~145MB) to $CACHE_DIR/ ..."
    HF_HOME="$CACHE_DIR" \
        /usr/local/bin/whisper /dev/null \
        --model base.en --language en --compute_type int8 \
        --output_format txt --output_dir /tmp \
        --verbose False 2>/dev/null | \
        grep -v "InvalidDataError\|Traceback\|File \"/" || true

    if [ -d "$MODEL_DIR" ]; then
        chmod -R a+rX "$CACHE_DIR" 2>/dev/null || true
        ok "Whisper base.en model downloaded to $CACHE_DIR/"
        HF_CACHE_DIR="$CACHE_DIR"
        return 0
    else
        warn "Model download failed — will download on first use"
        HF_CACHE_DIR="$CACHE_DIR"
        return 1
    fi
}

# ── Mimic 3 detection ─────────────────────────────────────────────────────────

detect_mimic3() {
    MIMIC3_BIN=""
    MIMIC3_METHOD=""

    if command -v mimic3 >/dev/null 2>&1; then
        MIMIC3_BIN=$(which mimic3)
        if dpkg -l mycroft-mimic3-tts >/dev/null 2>&1; then
            MIMIC3_METHOD="deb"
        else
            MIMIC3_METHOD="pip"
        fi
        return 0
    fi

    return 1
}

install_mimic3() {
    local MIMIC3_URL="https://github.com/MycroftAI/mimic3/releases/download/v0.2.4/mycroft-mimic3-tts_0.2.4_amd64.deb"
    local MIMIC3_DEB="/tmp/mycroft-mimic3-tts.deb"
    local DOWNLOAD_OK=false

    info "Attempting mimic3 install via official .deb ..."
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$MIMIC3_DEB" "$MIMIC3_URL" 2>/dev/null && DOWNLOAD_OK=true
    elif command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$MIMIC3_DEB" "$MIMIC3_URL" 2>/dev/null && DOWNLOAD_OK=true
    fi

    if [ "$DOWNLOAD_OK" = true ] && [ -f "$MIMIC3_DEB" ]; then
        dpkg -i "$MIMIC3_DEB" 2>/dev/null || apt-get --fix-broken install -y
        rm -f "$MIMIC3_DEB"
        MIMIC3_BIN=$(which mimic3 2>/dev/null)
        MIMIC3_METHOD="deb"
        ok "mimic3 installed via .deb"
        return 0
    fi

    # pip fallback
    warn ".deb download failed — trying pip install ..."
    if python3 -m pip install "mycroft-mimic3-tts[all]" --user --quiet 2>/dev/null; then
        MIMIC3_BIN=$(which mimic3 2>/dev/null)
        MIMIC3_METHOD="pip"
        ok "mimic3 installed via pip (user)"
        return 0
    fi

    warn "mimic3 could not be installed automatically."
    warn "Install manually from: https://github.com/MycroftAI/mimic3/releases"
    return 1
}
