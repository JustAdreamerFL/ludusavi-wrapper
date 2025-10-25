#!/usr/bin/env bash

# ============================================================================
# Ludusavi Universal Wrapper
# ============================================================================
# A cross-platform wrapper for automatic game save backup and restore
# Works with Lutris, Heroic Launcher, and other game launchers
# Supports Linux and macOS
#
# Features:
# - Auto-detects game names from launcher environment variables
# - Backs up saves before and after game sessions
# - Checks Syncthing sync status before launching
# - Updates ludusavi manifest when network is available
# - Triggers Syncthing rescan after backup
# ============================================================================

# Debug logging
echo "[$(date)] Running $0 as $USER in $PWD with args: $@" >> /tmp/ludusavi_wrapper_debug.log
env >> /tmp/ludusavi_wrapper_debug.log

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# ============================================================================
# QUICK HELP CHECK (before anything else)
# ============================================================================

# Check for help flag immediately to avoid unnecessary processing
for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    cat << 'EOF'
Ludusavi Universal Wrapper
==========================

Automatically backup and restore your game saves. Like Steam Cloud,
but works with ANY game.

WHAT IT DOES:
    • Restores your latest saves when you launch a game
    • Backs up your saves when you quit
    • Works with Heroic, Lutris, and any launcher that supports wrappers

BASIC USAGE:
    ludusavi-wrapper [OPTIONS] --mode=pre|post [--game-name="Game Name"]

OPTIONS:
    --cache              Enable caching of tool paths for faster startup
    --mode=MODE          Execution mode (default: wrapper)
    --game-name=NAME     Override game name (auto-detected if not set)
    -h, --help           Show this help message

LAUNCHER SETUP:
    In Heroic/Lutris wrapper/prefix field, add:
        /path/to/ludusavi-wrapper --cache (caching i recommend)



QUICK EXAMPLES:
    # Wrap any game (auto-detects game name)
    ludusavi-wrapper /path/to/game.exe

    # Recommended: enable caching for faster launches
    ludusavi-wrapper --cache /path/to/game.exe

    # Override game name if detection is wrong
    ludusavi-wrapper --game-name="The Witcher 3" /path/to/witcher3.exe

ADVANCED MODES:
    --mode=wrapper       Full cycle: restore → play → backup (default)
    --mode=pre           Only restore saves before launch
    --mode=post          Only backup saves after exit

    # Backup saves only (useful for shutdown scripts)
    ludusavi-wrapper --mode=post --game-name="My Game"

    # Restore saves only (useful for startup scripts)
    ludusavi-wrapper --mode=pre --game-name="My Game"

GAME NAME DETECTION:
    The wrapper automatically detects your game name from:
    1. --game-name argument (you specify it)
    2. Launcher environment variables (Heroic/Lutris)
    3. macOS .app bundle name
    4. Executable filename
    5. Current directory name

TIPS:
    • First run takes 1-2 seconds to find tools
    • With --cache, subsequent runs add only ~0.1 seconds
    • Works great with Syncthing for cross-device save sync
    • See full documentation: github.com/JustAdreamerFL/ludusavi-wrapper

EOF
    exit 0
  fi
done

# ============================================================================
# COMMAND-LINE ARGUMENT PARSING (must happen before tool detection)
# ============================================================================

# Mode selection: wrapper (default), pre, post
MODE="wrapper"
GAME_NAME_ARG=""
USE_CACHE=false

# Parse arguments first to determine if caching should be used
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      # Already handled above, but keep for completeness
      exit 0
      ;;
    --mode=*)
      MODE="${1#--mode=}"
      shift
      ;;
    --game-name=*)
      GAME_NAME_ARG="${1#--game-name=}"
      shift
      ;;
    --cache)
      USE_CACHE=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

# ============================================================================
# EARLY ARGUMENT VALIDATION (before tool detection for faster feedback)
# ============================================================================

# Validate that wrapper mode has a game executable
if [[ "$MODE" == "wrapper" && $# -eq 0 ]]; then
  echo "" >&2
  echo "Error: No game executable specified" >&2
  echo "" >&2
  echo "USAGE:" >&2
  echo "  $0 [--cache] [--game-name=NAME] <game_executable> [args...]" >&2
  echo "" >&2
  echo "EXAMPLES:" >&2
  echo "  $0 /path/to/game                              # Basic usage" >&2
  echo "  $0 --cache /path/to/game                      # With caching" >&2
  echo "  $0 --cache --game-name=\"My Game\" /path/to/game  # With custom name" >&2
  echo "" >&2
  echo "For full help, run: $0 --help" >&2
  echo "" >&2
  exit 2
fi

# Note: pre/post modes don't require --game-name if launcher env vars are set
# Validation happens later after game name detection

# ============================================================================
# CONFIGURATION
# ============================================================================

# Ludusavi executable path (auto-detected if not set)
LUDUSAVI="${LUDUSAVI_PATH:-}"

# Launcher type detection (auto-detected if not set)
# Options: "lutris", "heroic", "auto"
LAUNCHER_TYPE="${LAUNCHER_TYPE:-auto}"

# ============================================================================
# CACHE DIRECTORY SETUP
# ============================================================================

# Determine cache directory based on platform
if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  # Use XDG standard if available
  CACHE_DIR="${XDG_CACHE_HOME}"
elif [[ -d "$HOME/Library/Caches" ]]; then
  # macOS standard location
  CACHE_DIR="$HOME/Library/Caches/ludusavi-wrapper"
else
  # Linux fallback
  CACHE_DIR="$HOME/.cache"
fi

CACHE_FILE="${CACHE_DIR}/ludusavi_wrapper_path"
PING_CACHE_FILE="${CACHE_DIR}/ludusavi_wrapper_ping_cmd"

# ============================================================================
# LUDUSAVI AUTO-DETECTION
# ============================================================================
# Note: Cache validation ensures stale/invalid paths are automatically re-detected
# Handles cases like: executable moved, uninstalled, or switched between native/Flatpak

if [[ -z "${LUDUSAVI}" ]] || [[ ! -x "${LUDUSAVI}" ]]; then
  # Try to load from cache first (if caching is enabled)
  if [[ "${USE_CACHE}" == "true" && -f "${CACHE_FILE}" ]]; then
    CACHED_PATH=$(cat "${CACHE_FILE}" 2>/dev/null)

    # Validate cached path: check if it's executable or a valid Flatpak command
    if [[ -n "${CACHED_PATH}" ]]; then
      if [[ -x "${CACHED_PATH}" ]]; then
        # Regular executable file
        LUDUSAVI="${CACHED_PATH}"
        echo "Loaded ludusavi path from cache: ${LUDUSAVI}" >&2
      elif [[ "${CACHED_PATH}" == "flatpak run "* ]]; then
        # Flatpak command - verify flatpak is available
        if command -v flatpak >/dev/null 2>&1; then
          LUDUSAVI="${CACHED_PATH}"
          echo "Loaded ludusavi path from cache: ${LUDUSAVI}" >&2
        else
          echo "Cached Flatpak command invalid (flatpak not found), re-detecting..." >&2
        fi
      fi
    fi
  fi

  # If cache didn't work or caching disabled, search for ludusavi
  if [[ -z "${LUDUSAVI}" ]] || [[ ! -x "${LUDUSAVI}" ]]; then
    echo "Auto-detecting ludusavi location..." >&2

    # Common installation paths (prioritized by likelihood)
    # Order: Homebrew (Intel Mac), Homebrew (Apple Silicon), standard Linux paths
    LUDUSAVI_CANDIDATES=(
      "/usr/local/bin/ludusavi"
      "/opt/homebrew/bin/ludusavi"
      "/usr/bin/ludusavi"
      "$HOME/.local/bin/ludusavi"
      "$HOME/.cargo/bin/ludusavi"
      "$(command -v ludusavi 2>/dev/null || echo '')"
    )

    for candidate in "${LUDUSAVI_CANDIDATES[@]}"; do
      if [[ -n "${candidate}" ]] && [[ -x "${candidate}" ]]; then
        LUDUSAVI="${candidate}"
        echo "Found ludusavi at: ${LUDUSAVI}" >&2

        # Cache the found path for future runs (if caching is enabled)
        if [[ "${USE_CACHE}" == "true" ]]; then
          mkdir -p "$(dirname "${CACHE_FILE}")"
          echo "${LUDUSAVI}" > "${CACHE_FILE}"
          echo "Cached path for future use" >&2
        fi
        break
      fi
    done

    # Check for Flatpak installation (Linux)
    if [[ -z "${LUDUSAVI}" ]] || [[ ! -x "${LUDUSAVI}" ]]; then
      if command -v flatpak >/dev/null 2>&1 && flatpak list --app | grep -q "com.github.mtkennerly.ludusavi"; then
        LUDUSAVI="flatpak run com.github.mtkennerly.ludusavi"
        echo "Found ludusavi as Flatpak" >&2

        # Cache the flatpak command (if caching is enabled)
        if [[ "${USE_CACHE}" == "true" ]]; then
          mkdir -p "$(dirname "${CACHE_FILE}")"
          echo "${LUDUSAVI}" > "${CACHE_FILE}"
          echo "Cached flatpak command for future use" >&2
        fi
      fi
    fi

    # Exit if ludusavi not found
    if [[ -z "${LUDUSAVI}" ]]; then
      echo "Error: ludusavi not found!" >&2
      echo "Please install ludusavi or set LUDUSAVI_PATH environment variable" >&2
      echo "Tried locations: ${LUDUSAVI_CANDIDATES[*]}" >&2
      echo "Also checked for Flatpak installation" >&2
      exit 1
    fi
  fi
fi

# ============================================================================
# LAUNCHER & GAME NAME DETECTION
# ============================================================================

GAME_NAME=""

# Auto-detect launcher type from environment variables
if [[ "${LAUNCHER_TYPE}" == "auto" ]]; then
  if [[ -n "${LUTRIS_GAME_NAME:-}" ]] || [[ -n "${LUTRIS_GAME_ID:-}" ]]; then
    LAUNCHER_TYPE="lutris"
  elif [[ -n "${HEROIC_APP_NAME:-}" ]] || [[ -n "${HEROIC_GAMES_LAUNCHER_GAME_TITLE:-}" ]]; then
    LAUNCHER_TYPE="heroic"
  else
    LAUNCHER_TYPE="unknown"
  fi
fi

# Extract game name from various sources (priority order)
# 1. Command-line argument
if [[ -n "${GAME_NAME_ARG}" ]]; then
  GAME_NAME="${GAME_NAME_ARG}"

# 2. Lutris environment variables
elif [[ "${LAUNCHER_TYPE}" == "lutris" ]]; then
  GAME_NAME="${LUTRIS_GAME_NAME:-}"
  if [[ -z "${GAME_NAME}" ]]; then
    GAME_NAME="${LUTRIS_GAME_ID:-}"
  fi

# 3. Heroic environment variables
elif [[ "${LAUNCHER_TYPE}" == "heroic" ]]; then
  GAME_NAME="${HEROIC_GAMES_LAUNCHER_GAME_TITLE:-}"

  # Check if HEROIC_APP_NAME looks like an ID (alphanumeric hash)
  if [[ -z "${GAME_NAME}" ]] && [[ -n "${HEROIC_APP_NAME:-}" ]]; then
    if [[ "${HEROIC_APP_NAME}" =~ ^[a-zA-Z0-9]{20,}$ ]]; then
      # It's an ID, skip it
      GAME_NAME=""
    else
      GAME_NAME="${HEROIC_APP_NAME}"
    fi
  fi
fi

# 4. Extract from executable path or working directory
if [[ -z "${GAME_NAME}" ]]; then
  if [[ "$MODE" == "wrapper" && $# -gt 0 ]]; then
    game_exe="$1"

    # Try to extract from macOS .app bundle
    if [[ "$game_exe" =~ /([^/]+)\.app/Contents/ ]]; then
      GAME_NAME="${BASH_REMATCH[1]}"
    else
      # Use executable filename without extension
      GAME_NAME=$(basename "$game_exe")
      GAME_NAME="${GAME_NAME%.*}"
    fi
    echo "Detected game name from path: ${GAME_NAME}" >&2

  else
    # Fallback: use current directory name, skipping common subdirectories
    current_dir=$(basename "$PWD")

    # Skip common game subdirectories (bin, x64, lib, etc.)
    if [[ "$current_dir" =~ ^(bin|x64|x86|x86_64|i386|i686|amd64|lib|lib64|lib32|data|game)$ ]]; then
      parent_dir=$(basename "$(dirname "$PWD")")

      if [[ "$parent_dir" =~ ^(bin|x64|x86|x86_64|i386|i686|amd64|lib|lib64|lib32|data|game)$ ]]; then
        grandparent_dir=$(basename "$(dirname "$(dirname "$PWD")")")

        if [[ "$grandparent_dir" =~ ^(bin|x64|x86|x86_64|i386|i686|amd64|lib|lib64|lib32|data|game)$ ]]; then
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

# ============================================================================
# VALIDATE GAME NAME (after detection)
# ============================================================================

# For pre/post modes, ensure we have a game name
if [[ ("$MODE" == "pre" || "$MODE" == "post") && -z "${GAME_NAME}" ]]; then
  echo "" >&2
  echo "Error: Could not detect game name for --mode=$MODE" >&2
  echo "" >&2
  echo "Game name detection failed. This can happen when:" >&2
  echo "  - Running outside a launcher (no env vars set)" >&2
  echo "  - Running from a directory that doesn't contain the game name" >&2
  echo "" >&2
  echo "SOLUTIONS:" >&2
  echo "  1. Specify game name explicitly:" >&2
  echo "     $0 --mode=$MODE --game-name=\"Game Name\"" >&2
  echo "" >&2
  echo "  2. Run from the game's directory:" >&2
  echo "     cd /path/to/Game && $0 --mode=$MODE" >&2
  echo "" >&2
  echo "  3. Use from within a launcher (Lutris/Heroic) that sets env vars" >&2
  echo "" >&2
  exit 3
fi

# ============================================================================
# DISPLAY SESSION INFORMATION
# ============================================================================

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

# ============================================================================
# SYNCTHING CLI (stc) AUTO-DETECTION
# ============================================================================

STC_CMD=""

if command -v stc >/dev/null 2>&1; then
  STC_CMD="stc"
else
  # Search common installation paths
  # Order: user Go bin, user local, Homebrew (both variants), system
  STC_CANDIDATES=(
    "$HOME/go/bin/stc"
    "$HOME/.local/bin/stc"
    "/usr/local/bin/stc"
    "/opt/homebrew/bin/stc"
    "/usr/bin/stc"
  )

  for candidate in "${STC_CANDIDATES[@]}"; do
    if [[ -x "${candidate}" ]]; then
      STC_CMD="${candidate}"
      break
    fi
  done
fi

# ============================================================================
# SYNCTHING SYNC STATUS CHECK
# ============================================================================

echo "Checking Syncthing sync status for ludusavi_server folder..." >&2

SYNC_CHECK_COMPLETE=false
SYNC_PERCENTAGE=0

if [[ -n "${STC_CMD}" ]]; then
  # Try JSON API first (more reliable)
  if stc_output=$("${STC_CMD}" json_dump 2>/dev/null); then
    # Parse JSON for ludusavi_server folder sync percentage
    # grep -o is compatible with both GNU (Linux) and BSD (macOS) grep
    SYNC_PERCENTAGE=$(echo "${stc_output}" | \
      grep -o '"folderName":"ludusavi_server"[^}]*' | \
      grep -o '"syncPercentDone":[0-9]*' | \
      grep -o '[0-9]*' | \
      head -1 || echo "0")

    if [[ -n "${SYNC_PERCENTAGE}" ]]; then
      SYNC_CHECK_COMPLETE=true
      echo "Syncthing sync status: ${SYNC_PERCENTAGE}%" >&2
    fi
  fi

  # Fallback to text-based status command
  if [[ "${SYNC_CHECK_COMPLETE}" == "false" ]]; then
    if stc_output=$("${STC_CMD}" status ludusavi_server 2>/dev/null); then
      SYNC_PERCENTAGE=$(echo "${stc_output}" | \
        grep "ludusavi_server" | \
        awk '{print $3}' | \
        sed 's/%//' || echo "0")

      if [[ -n "${SYNC_PERCENTAGE}" && "${SYNC_PERCENTAGE}" != "0" ]]; then
        SYNC_CHECK_COMPLETE=true
        echo "Syncthing sync status: ${SYNC_PERCENTAGE}%" >&2
      fi
    fi
  fi

  # Show GUI warning if not fully synced
  if [[ "${SYNC_CHECK_COMPLETE}" == "true" && "${SYNC_PERCENTAGE}" != "100" ]]; then
    WARNING_MSG="WARNING: Syncthing folder is not fully synced!\n\nCurrent sync: ${SYNC_PERCENTAGE}%\nGame: ${GAME_NAME}\n\nThe game will run, but your saves may not be up to date.\n\nWait for sync to complete before continuing?"

    echo "WARNING: Syncthing folder is not fully synced (${SYNC_PERCENTAGE}%)!" >&2
    echo "Game will run anyway, but saves may not be up to date." >&2

    # Try to show GUI notification based on available tools
    if command -v osascript >/dev/null 2>&1; then
      # macOS: AppleScript dialog (10 second timeout)
      osascript -e "display dialog \"${WARNING_MSG}\" buttons {\"Continue Anyway\"} default button 1 with icon caution with title \"Ludusavi Sync Warning\" giving up after 10" >/dev/null 2>&1 &
    elif command -v notify-send >/dev/null 2>&1; then
      # Linux: notify-send (desktop notification)
      notify-send -u critical -t 10000 "Ludusavi Sync Warning" "Syncthing not synced (${SYNC_PERCENTAGE}%)!\nGame: ${GAME_NAME}\n\nSaves may not be up to date." >/dev/null 2>&1 &
    elif command -v zenity >/dev/null 2>&1; then
      # Linux: Zenity dialog
      (zenity --warning --text="${WARNING_MSG}" --title="Ludusavi Sync Warning" --timeout=10 >/dev/null 2>&1) &
    elif command -v kdialog >/dev/null 2>&1; then
      # Linux KDE: KDialog
      (kdialog --sorry "${WARNING_MSG}" --title "Ludusavi Sync Warning" >/dev/null 2>&1) &
    fi

    # Wait briefly to ensure dialog appears
    sleep 1
  fi
else
  echo "Note: stc (Syncthing CLI) not found. Skipping sync status check." >&2
fi

echo ""

# ============================================================================
# NETWORK CONNECTIVITY CHECK
# ============================================================================

MANIFEST_UPDATE_FLAG=""
PING_CMD=""

# Load cached ping command if available (if caching is enabled)
if [[ "${USE_CACHE}" == "true" && -f "${PING_CACHE_FILE}" ]]; then
  PING_CMD=$(cat "${PING_CACHE_FILE}" 2>/dev/null)
  if [[ -n "${PING_CMD}" ]]; then
    echo "Loaded ping command from cache: ${PING_CMD}" >&2
  fi
fi

# Detect appropriate ping timeout flag for cross-platform compatibility
# Different systems interpret ping timeout flags differently:
# - macOS/BSD: -W is milliseconds
# - Linux iputils: -W is seconds
# - BusyBox: -w is milliseconds
if [[ -z "${PING_CMD}" ]]; then
  if ping -c 1 -W 100 127.0.0.1 >/dev/null 2>&1; then
    # macOS/BSD: -W in milliseconds (use 300ms for speed)
    PING_CMD="ping -c 1 -W 300"
  elif ping -c 1 -W 1 127.0.0.1 >/dev/null 2>&1; then
    # Linux iputils: -W in seconds (1s minimum)
    PING_CMD="ping -c 1 -W 1"
  elif ping -c 1 -w 300 127.0.0.1 >/dev/null 2>&1; then
    # BusyBox: -w in milliseconds
    PING_CMD="ping -c 1 -w 300"
  else
    # Fallback: basic ping with default timeout
    PING_CMD="ping -c 1"
  fi

  # Prefer IPv4 to avoid IPv6/AAAA lookup delays
  if ping -c 1 -4 127.0.0.1 >/dev/null 2>&1; then
    PING_CMD="ping -4 ${PING_CMD#ping }"
  fi

  # Cache the detected command for future runs (if caching is enabled)
  if [[ "${USE_CACHE}" == "true" ]]; then
    mkdir -p "$(dirname "${PING_CACHE_FILE}")"
    echo "${PING_CMD}" > "${PING_CACHE_FILE}"
    echo "Cached ping command for future use" >&2
  fi
fi

# Fast online check using multiple anycast DNS servers
# Tries Cloudflare, Google, and Quad9 in order (optimized for EU)
fast_online_check() {
  local cmd="$PING_CMD"
  for host in 1.1.1.1 8.8.8.8 9.9.9.9; do
    if $cmd "$host" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# Check connectivity and set manifest update flag
if fast_online_check; then
  echo "Network detected, will try to update manifest..." >&2
  MANIFEST_UPDATE_FLAG="--try-manifest-update"
else
  echo "No network detected, skipping manifest update..." >&2
  MANIFEST_UPDATE_FLAG="--no-manifest-update"
fi

# ============================================================================
# HELPER FUNCTION: TRIGGER SYNCTHING RESCAN
# ============================================================================

trigger_syncthing_rescan() {
  if [[ -n "${STC_CMD}" ]]; then
    echo "Triggering Syncthing rescan for ludusavi_server folder..." >&2
    if "${STC_CMD}" rescan ludusavi_server 2>/dev/null; then
      echo "Syncthing rescan triggered successfully." >&2
    else
      echo "Warning: Failed to trigger Syncthing rescan." >&2
    fi
  else
    echo "Note: stc (Syncthing CLI) not found. Skipping Syncthing rescan." >&2
  fi
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

if [[ "$MODE" == "pre" ]]; then
  # PRE-LAUNCH MODE: Restore saves only
  if [[ -z "${GAME_NAME}" ]]; then
    echo "Error: GAME_NAME is empty. Set --game-name= or ensure launcher environment variables are set." >&2
    exit 3
  fi

  echo "Running in PRE-LAUNCH mode: restoring saves only..." >&2
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} restore --force --gui --name "${GAME_NAME}"
  exit_code=$?

  if [[ -z "${exit_code:-}" ]]; then exit_code=0; fi
  echo "========================================"
  echo "Ludusavi restore completed with code: ${exit_code}"
  echo "========================================"

  trigger_syncthing_rescan
  exit ${exit_code}

elif [[ "$MODE" == "post" ]]; then
  # POST-LAUNCH MODE: Backup saves only
  if [[ -z "${GAME_NAME}" ]]; then
    echo "Error: GAME_NAME is empty. Set --game-name= or ensure launcher environment variables are set." >&2
    exit 3
  fi

  echo "Running in POST-LAUNCH mode: backing up saves only..." >&2
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} backup --force --gui --name "${GAME_NAME}"
  exit_code=$?

  if [[ -z "${exit_code:-}" ]]; then exit_code=0; fi
  echo "========================================"
  echo "Ludusavi backup completed with code: ${exit_code}"
  echo "========================================"

  trigger_syncthing_rescan
  exit ${exit_code}

else
  # WRAPPER MODE: Restore, run game, backup
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} wrap \
    --name "${GAME_NAME}" \
    --force \
    --gui \
    -- "$@"
  exit_code=$?

  echo ""
  echo "========================================"
  echo "Game exited with code: ${exit_code}"
  echo "Backup completed!"
  echo "========================================"

  trigger_syncthing_rescan
  exit ${exit_code}
fi
