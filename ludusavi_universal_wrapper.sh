#!/usr/bin/env bash
echo "[$(date)] Running $0 as $USER in $PWD with args: $@" >> /tmp/ludusavi_wrapper_debug.log
env >> /tmp/ludusavi_wrapper_debug.log
set -euo pipefail

# Universal Ludusavi wrapper for any game launcher (Lutris, Heroic, etc.)
# Use this as the game executable in your launcher settings for any game
# The game name is automatically detected from various sources

# ============================================================================
# CONFIGURATION - Edit these paths for your system
# ============================================================================

# Ludusavi executable path - will auto-detect if not set or if file doesn't exist
LUDUSAVI="${LUDUSAVI_PATH:-}"

# Cache file to store detected ludusavi path
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/ludusavi_wrapper_path"
PING_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/ludusavi_wrapper_ping_cmd"

# Launcher type detection (auto-detected if not set)
# Options: "lutris", "heroic", "auto"
LAUNCHER_TYPE="${LAUNCHER_TYPE:-auto}"

# ============================================================================
# Auto-detect ludusavi if not configured or path doesn't exist
# ============================================================================
if [[ -z "${LUDUSAVI}" ]] || [[ ! -x "${LUDUSAVI}" ]]; then
  # Try to load from cache first
  if [[ -f "${CACHE_FILE}" ]]; then
    CACHED_PATH=$(cat "${CACHE_FILE}" 2>/dev/null)
    if [[ -n "${CACHED_PATH}" ]] && [[ -x "${CACHED_PATH}" ]]; then
      LUDUSAVI="${CACHED_PATH}"
    fi
  fi
  
  # If cache didn't work, search for ludusavi
  if [[ -z "${LUDUSAVI}" ]] || [[ ! -x "${LUDUSAVI}" ]]; then
    echo "Auto-detecting ludusavi location..." >&2
    
    # Try common locations
    LUDUSAVI_CANDIDATES=(
      "/usr/bin/ludusavi"
      "/usr/local/bin/ludusavi"
      "$HOME/.local/bin/ludusavi"
      "$HOME/.cargo/bin/ludusavi"
      "/opt/homebrew/bin/ludusavi"
      "$(which ludusavi 2>/dev/null || echo '')"
    )
    
    for candidate in "${LUDUSAVI_CANDIDATES[@]}"; do
      if [[ -n "${candidate}" ]] && [[ -x "${candidate}" ]]; then
        LUDUSAVI="${candidate}"
        echo "Found ludusavi at: ${LUDUSAVI}" >&2
        
        # Cache the found path
        mkdir -p "$(dirname "${CACHE_FILE}")"
        echo "${LUDUSAVI}" > "${CACHE_FILE}"
        echo "Cached path for future use" >&2
        break
      fi
    done
    
    # If not found as native binary, check for Flatpak
    if [[ -z "${LUDUSAVI}" ]] || [[ ! -x "${LUDUSAVI}" ]]; then
      if command -v flatpak >/dev/null 2>&1 && flatpak list --app | grep -q "com.github.mtkennerly.ludusavi"; then
        LUDUSAVI="flatpak run com.github.mtkennerly.ludusavi"
        echo "Found ludusavi as Flatpak" >&2
        
        # Cache the flatpak command
        mkdir -p "$(dirname "${CACHE_FILE}")"
        echo "${LUDUSAVI}" > "${CACHE_FILE}"
        echo "Cached flatpak command for future use" >&2
      fi
    fi
    
    if [[ -z "${LUDUSAVI}" ]]; then
      echo "Error: ludusavi not found!" >&2
      echo "Please install ludusavi or set LUDUSAVI_PATH environment variable" >&2
      echo "Tried locations: ${LUDUSAVI_CANDIDATES[*]}" >&2
      echo "Also checked for Flatpak installation" >&2
      exit 1
    fi
  fi
fi

# The actual game executable should be passed as arguments


# Mode selection: wrapper (default), pre, post
MODE="wrapper"
GAME_NAME_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode=*)
      MODE="${1#--mode=}"
      shift
      ;;
    --game-name=*)
      GAME_NAME_ARG="${1#--game-name=}"
      shift
      ;;
    *)
      break
      ;;
  esac
done

# In wrapper mode, require a game executable
if [[ "$MODE" == "wrapper" && $# -eq 0 ]]; then
  echo "Error: No game executable specified" >&2
  echo "Usage: This script should wrap the actual game command" >&2
  exit 2
fi

# In wrapper mode, require a game executable
if [[ "$MODE" == "wrapper" && $# -eq 0 ]]; then
  echo "Error: No game executable specified" >&2
  echo "Usage: This script should wrap the actual game command" >&2
  exit 2
fi

# ============================================================================
# Detect game name from launcher environment variables
# ============================================================================

GAME_NAME=""

# Auto-detect launcher type if set to auto
if [[ "${LAUNCHER_TYPE}" == "auto" ]]; then
  if [[ -n "${LUTRIS_GAME_NAME:-}" ]] || [[ -n "${LUTRIS_GAME_ID:-}" ]]; then
    LAUNCHER_TYPE="lutris"
  elif [[ -n "${HEROIC_APP_NAME:-}" ]] || [[ -n "${HEROIC_GAMES_LAUNCHER_GAME_TITLE:-}" ]]; then
    LAUNCHER_TYPE="heroic"
  else
    LAUNCHER_TYPE="unknown"
  fi
fi

# Try Lutris environment variables
if [[ -n "${GAME_NAME_ARG}" ]]; then
  GAME_NAME="${GAME_NAME_ARG}"
elif [[ "${LAUNCHER_TYPE}" == "lutris" ]]; then
  GAME_NAME="${LUTRIS_GAME_NAME:-}"
  # Fall back to LUTRIS_GAME_ID if LUTRIS_GAME_NAME is not set
  if [[ -z "${GAME_NAME}" ]]; then
    GAME_NAME="${LUTRIS_GAME_ID:-}"
  fi
fi

# Try Heroic environment variables
if [[ "${LAUNCHER_TYPE}" == "heroic" ]]; then
  GAME_NAME="${HEROIC_GAMES_LAUNCHER_GAME_TITLE:-}"
  
  # If HEROIC_APP_NAME is set but looks like an ID (contains letters/numbers mix), 
  # extract from path instead
  if [[ -z "${GAME_NAME}" ]] && [[ -n "${HEROIC_APP_NAME:-}" ]]; then
    # Check if it looks like an app ID (alphanumeric hash)
    if [[ "${HEROIC_APP_NAME}" =~ ^[a-zA-Z0-9]{20,}$ ]]; then
      # It's probably an ID, extract from path instead
      GAME_NAME=""
    else
      GAME_NAME="${HEROIC_APP_NAME}"
    fi
  fi
fi

# If we still don't have a useful game name, extract it from the executable path or working directory
if [[ -z "${GAME_NAME}" ]]; then
  if [[ "$MODE" == "wrapper" && $# -gt 0 ]]; then
    # Get the first argument (the executable path)
    game_exe="$1"
    # Try to extract game name from .app bundle (macOS)
    if [[ "$game_exe" =~ /([^/]+)\.app/Contents/ ]]; then
      GAME_NAME="${BASH_REMATCH[1]}"
    else
      # Fall back to executable filename without extension
      GAME_NAME=$(basename "$game_exe" | sed 's/\.[^.]*$//')
    fi
    echo "Detected game name from path: ${GAME_NAME}" >&2
  else
    # Fallback: use last directory in $PWD, but skip common subdirs like bin, x64, x86, etc.
    current_dir=$(basename "$PWD")
    
    # List of common subdirectories to skip
    if [[ "$current_dir" =~ ^(bin|x64|x86|x86_64|i386|i686|amd64|lib|lib64|lib32|data|game)$ ]]; then
      # Go up one or more directories to find the actual game name
      parent_dir=$(basename "$(dirname "$PWD")")
      if [[ "$parent_dir" =~ ^(bin|x64|x86|x86_64|i386|i686|amd64|lib|lib64|lib32|data|game)$ ]]; then
        # Go up one more level
        grandparent_dir=$(basename "$(dirname "$(dirname "$PWD")")")
        if [[ "$grandparent_dir" =~ ^(bin|x64|x86|x86_64|i386|i686|amd64|lib|lib64|lib32|data|game)$ ]]; then
          # Go up one more level (last resort)
          GAME_NAME=$(basename "$(dirname "$(dirname "$(dirname "$PWD")")")")
        else
          GAME_NAME="$grandparent_dir"
        fi
      else
        GAME_NAME="$parent_dir"
      fi
    else
      GAME_NAME="$current_dir"
    fi
    
    echo "Detected game name from working directory: ${GAME_NAME}" >&2
  fi
fi


echo "========================================"
echo "Ludusavi Wrapper for ${GAME_NAME}"
echo "========================================"
echo "Launcher: ${LAUNCHER_TYPE}"
echo "Ludusavi: ${LUDUSAVI}"
echo "Command: $@"
echo ""
echo "Environment variables:"
if [[ "${LAUNCHER_TYPE}" == "lutris" ]]; then
  echo "  LUTRIS_GAME_NAME: ${LUTRIS_GAME_NAME:-<not set>}"
  echo "  LUTRIS_GAME_ID: ${LUTRIS_GAME_ID:-<not set>}"
elif [[ "${LAUNCHER_TYPE}" == "heroic" ]]; then
  echo "  HEROIC_APP_NAME: ${HEROIC_APP_NAME:-<not set>}"
  echo "  HEROIC_GAMES_LAUNCHER_GAME_TITLE: ${HEROIC_GAMES_LAUNCHER_GAME_TITLE:-<not set>}"
else
  echo "  (Launcher-specific variables not detected)"
fi
echo "========================================"
echo ""

# Quick network check (0.5 second timeout)
# If we can reach a DNS server, we probably have internet
MANIFEST_UPDATE_FLAG=""

# Try to load cached ping command
PING_CMD=""
if [[ -f "${PING_CACHE_FILE}" ]]; then
  PING_CMD=$(cat "${PING_CACHE_FILE}" 2>/dev/null)
fi

# If no cached command or cache is invalid, detect which ping flag the system uses
if [[ -z "${PING_CMD}" ]]; then
  if ping -c 1 -W 0.5 127.0.0.1 >/dev/null 2>&1; then
    # System uses -W flag (most Linux)
    PING_CMD="ping -c 1 -W 0.5 8.8.8.8"
  elif ping -c 1 -w 500 127.0.0.1 >/dev/null 2>&1; then
    # System uses -w flag with milliseconds (some Linux variants)
    PING_CMD="ping -c 1 -w 500 8.8.8.8"
  else
    # Fallback: just use basic ping with 1 packet
    PING_CMD="ping -c 1 8.8.8.8"
  fi
  
  # Cache the detected ping command
  mkdir -p "$(dirname "${PING_CACHE_FILE}")"
  echo "${PING_CMD}" > "${PING_CACHE_FILE}"
fi

if $PING_CMD >/dev/null 2>&1; then
  echo "Network detected, will try to update manifest..." >&2
  MANIFEST_UPDATE_FLAG="--try-manifest-update"
else
  echo "No network detected, skipping manifest update..." >&2
  MANIFEST_UPDATE_FLAG="--no-manifest-update"
fi



if [[ "$MODE" == "pre" ]]; then
  if [[ -z "${GAME_NAME}" ]]; then
    echo "Error: GAME_NAME is empty. Set --game-name= or ensure LUTRIS_GAME_NAME is set." >&2
    exit 3
  fi
  echo "Running in PRE-LAUNCH mode: restoring saves only..." >&2
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} restore --force --gui "${GAME_NAME}"
  exit_code=$?
  if [[ -z "${exit_code:-}" ]]; then exit_code=0; fi
  echo "========================================"
  echo "Ludusavi restore completed with code: ${exit_code}"
  echo "========================================"
  exit ${exit_code}
elif [[ "$MODE" == "post" ]]; then
  if [[ -z "${GAME_NAME}" ]]; then
    echo "Error: GAME_NAME is empty. Set --game-name= or ensure LUTRIS_GAME_NAME is set." >&2
    exit 3
  fi
  echo "Running in POST-LAUNCH mode: backing up saves only..." >&2
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} backup --force --gui "${GAME_NAME}"
  exit_code=$?
  if [[ -z "${exit_code:-}" ]]; then exit_code=0; fi
  echo "========================================"
  echo "Ludusavi backup completed with code: ${exit_code}"
  echo "========================================"
  exit ${exit_code}
else
  # Wrapper mode: restore, run game, backup
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} wrap \
    --force \
    --gui \
    "${GAME_NAME}" \
    -- "$@"
  exit_code=$?
  echo ""
  echo "========================================"
  echo "Game exited with code: ${exit_code}"
  echo "Backup completed!"
  echo "========================================"
  exit ${exit_code}
fi
