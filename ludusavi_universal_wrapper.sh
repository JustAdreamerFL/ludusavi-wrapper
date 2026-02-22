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

# Track whether user chose to skip all ludusavi operations
SKIP_LUDUSAVI=false

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# URL-encode a string for use in API queries
url_encode() {
  local string="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -rn --arg s "$string" '$s|@uri'
  elif command -v curl >/dev/null 2>&1; then
    # Use curl's --data-urlencode with a dummy request to encode the string
    curl -s -o /dev/null -w '%{url_effective}' --get --data-urlencode "q=$string" "" 2>/dev/null | sed 's/^.*?q=//' | sed 's/&.*$//'
  else
    # Pure bash/sed fallback: encode the most common special characters
    echo "$string" | sed \
      -e 's/%/%25/g' \
      -e 's/ /%20/g' \
      -e 's/:/%3A/g' \
      -e 's/!/%21/g' \
      -e "s/'/%27/g" \
      -e 's/(/%28/g' \
      -e 's/)/%29/g' \
      -e 's/&/%26/g' \
      -e 's/+/%2B/g' \
      -e 's/,/%2C/g' \
      -e 's/;/%3B/g' \
      -e 's/=/%3D/g' \
      -e 's/?/%3F/g' \
      -e 's/@/%40/g' \
      -e 's/#/%23/g'
  fi
}

# Search PCGamingWiki for a game name and return matching titles (one per line)
pcgamingwiki_lookup() {
  local search_term="$1"
  local encoded_term
  encoded_term=$(url_encode "$search_term")

  local results=""

  # Try opensearch first (prefix matching - cleaner results)
  local api_url="https://www.pcgamingwiki.com/w/api.php?action=opensearch&search=${encoded_term}&limit=10&format=json"
  local response
  response=$(curl -s --max-time 10 "$api_url" 2>/dev/null || echo "")

  if [[ -n "$response" ]]; then
    if command -v jq >/dev/null 2>&1; then
      results=$(echo "$response" | jq -r '.[1][]' 2>/dev/null)
    else
      # Fallback: opensearch returns ["term",["Title1","Title2",...],...]
      # Extract the second JSON array and pull out quoted strings
      results=$(echo "$response" | sed 's/.*\["\([^]]*\)"\].*/\1/' | grep -oP '(?<=")[^"]+(?=")' 2>/dev/null | head -10)
    fi
  fi

  # If no results from opensearch, try full-text search API
  if [[ -z "$results" ]]; then
    api_url="https://www.pcgamingwiki.com/w/api.php?action=query&list=search&srsearch=${encoded_term}&format=json&srlimit=10"
    response=$(curl -s --max-time 10 "$api_url" 2>/dev/null || echo "")

    if [[ -n "$response" ]]; then
      if command -v jq >/dev/null 2>&1; then
        results=$(echo "$response" | jq -r '.query.search[].title' 2>/dev/null)
      else
        # Fallback: extract "title":"Value" pairs from the JSON response
        results=$(echo "$response" | grep -oP '"title"\s*:\s*"\K[^"]+' 2>/dev/null | head -10)
      fi
    fi
  fi

  echo "$results"
}

# Try a ludusavi operation. On failure, offer a GUI dialog to either skip ludusavi
# entirely or look up the correct name on PCGamingWiki and retry.
#
# Usage: run_ludusavi_op <"restore"|"backup">
# Side effects: may update GAME_NAME and set SKIP_LUDUSAVI=true
# Returns: 0 on success, 1 if user chose to skip, 2+ on unrecoverable error
run_ludusavi_op() {
  local operation="$1"

  # If user already chose to skip ludusavi (e.g. during restore), honour that
  if [[ "${SKIP_LUDUSAVI}" == "true" ]]; then
    echo "Skipping ludusavi ${operation} (user chose to skip earlier)." >&2
    return 1
  fi

  local escaped_name
  escaped_name=$(printf %q "${GAME_NAME}")

  echo "Debug: Executing ${operation} command: ${LUDUSAVI} ${MANIFEST_UPDATE_FLAG} ${operation} --force --gui ${escaped_name}" >&2

  set +e
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} "${operation}" --force --gui "${escaped_name}"
  local lud_exit=$?
  set -e

  # Success on first try — nothing else to do
  if [[ ${lud_exit} -eq 0 ]]; then
    echo "Ludusavi ${operation} succeeded for '${GAME_NAME}'." >&2
    return 0
  fi

  echo "Ludusavi ${operation} failed (exit code ${lud_exit}) for '${GAME_NAME}'." >&2

  # If no graphical display or no zenity, we can't show a dialog — just report and return
  if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || ! command -v zenity >/dev/null 2>&1; then
    echo "No display or zenity available — cannot show fallback dialog." >&2
    return ${lud_exit}
  fi

  # ---- Failure dialog: two choices ----
  local choice
  choice=$(zenity --list --radiolist \
    --title="Ludusavi ${operation} failed" \
    --text="Ludusavi <b>${operation}</b> failed for:\n\n<b>${GAME_NAME}</b>\n(exit code: ${lud_exit})\n\nWhat would you like to do?" \
    --column="Pick" --column="Action" \
    TRUE  "Continue without ludusavi" \
    FALSE "Look up on PCGamingWiki" \
    --width=500 --height=320 2>/dev/null) || true

  # ---- Choice 1: skip ludusavi ----
  if [[ "$choice" != "Look up on PCGamingWiki" ]]; then
    echo "User chose to continue without ludusavi." >&2
    SKIP_LUDUSAVI=true
    return 1
  fi

  # ---- Choice 2: PCGamingWiki lookup ----
  echo "User requested PCGamingWiki lookup for '${GAME_NAME}'..." >&2

  local wiki_results
  wiki_results=$(pcgamingwiki_lookup "${GAME_NAME}")

  if [[ -z "$wiki_results" ]]; then
    zenity --warning --title="PCGamingWiki Lookup" \
      --text="No results found on PCGamingWiki for:\n\n<b>${GAME_NAME}</b>\n\nContinuing without ludusavi." \
      --width=400 2>/dev/null || true
    echo "No PCGamingWiki results for '${GAME_NAME}'. Skipping ludusavi." >&2
    SKIP_LUDUSAVI=true
    return 1
  fi

  echo "PCGamingWiki returned results:" >&2
  echo "$wiki_results" >&2

  # Build zenity list arguments
  local zenity_args=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && zenity_args+=("$line")
  done <<< "$wiki_results"

  local selected_name
  selected_name=$(zenity --list \
    --title="PCGamingWiki Results" \
    --text="Search results for: <b>${GAME_NAME}</b>\n\nSelect the correct game name:" \
    --column="Game Name" \
    "${zenity_args[@]}" \
    --width=550 --height=450 2>/dev/null) || true

  if [[ -z "$selected_name" ]]; then
    echo "User cancelled PCGamingWiki selection. Skipping ludusavi." >&2
    SKIP_LUDUSAVI=true
    return 1
  fi

  echo "User selected '${selected_name}' from PCGamingWiki. Retrying ${operation}..." >&2
  GAME_NAME="$selected_name"
  escaped_name=$(printf %q "${GAME_NAME}")

  # ---- Retry with the wiki name ----
  set +e
  eval "${LUDUSAVI}" ${MANIFEST_UPDATE_FLAG} "${operation}" --force --gui "${escaped_name}"
  local retry_exit=$?
  set -e

  if [[ ${retry_exit} -eq 0 ]]; then
    echo "Ludusavi ${operation} succeeded with wiki name '${GAME_NAME}'." >&2
    return 0
  fi

  # Retry also failed — show error dialog
  echo "Ludusavi ${operation} still failed (exit code ${retry_exit}) with wiki name '${GAME_NAME}'." >&2
  zenity --error --title="Ludusavi Error" \
    --text="Ludusavi <b>${operation}</b> still failed after PCGamingWiki lookup.\n\nGame name: <b>${GAME_NAME}</b>\nExit code: ${retry_exit}\n\nThe name from PCGamingWiki may not match what\nLudusavi expects. You may need to add a custom\ngame entry in Ludusavi.\n\nContinuing without ludusavi." \
    --width=450 2>/dev/null || true
  SKIP_LUDUSAVI=true
  return ${retry_exit}
}

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

# Strip leading non-alphanumeric characters (spaces, dashes, underscores, etc.)
# from the final game name, regardless of how it was detected
GAME_NAME_ORIGINAL="${GAME_NAME}"
GAME_NAME=$(echo "${GAME_NAME}" | sed 's/^[^[:alnum:]]*//')
if [[ "${GAME_NAME}" != "${GAME_NAME_ORIGINAL}" ]]; then
  echo "Stripped leading non-alphanumeric characters from game name: '${GAME_NAME_ORIGINAL}' -> '${GAME_NAME}'" >&2
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

  run_ludusavi_op "restore"
  op_result=$?

  echo "========================================"
  if [[ ${op_result} -eq 0 ]]; then
    echo "Ludusavi restore completed successfully."
  elif [[ ${op_result} -eq 1 ]]; then
    echo "Ludusavi restore skipped by user."
  else
    echo "Ludusavi restore failed (exit code: ${op_result})."
  fi
  echo "========================================"
  exit 0

elif [[ "$MODE" == "post" ]]; then
  if [[ -z "${GAME_NAME}" ]]; then
    echo "Error: GAME_NAME is empty. Set --game-name= or ensure LUTRIS_GAME_NAME is set." >&2
    exit 3
  fi
  echo "Running in POST-LAUNCH mode: backing up saves only..." >&2

  run_ludusavi_op "backup"
  op_result=$?

  echo "========================================"
  if [[ ${op_result} -eq 0 ]]; then
    echo "Ludusavi backup completed successfully."
  elif [[ ${op_result} -eq 1 ]]; then
    echo "Ludusavi backup skipped by user."
  else
    echo "Ludusavi backup failed (exit code: ${op_result})."
  fi
  echo "========================================"
  exit 0

else
  # Wrapper mode: restore, run game, backup

  # 1. Restore (failure here does not prevent game launch)
  run_ludusavi_op "restore"
  restore_result=$?

  if [[ ${restore_result} -eq 0 ]]; then
    echo "Restore completed successfully." >&2
  elif [[ ${restore_result} -eq 1 ]]; then
    echo "Restore skipped by user." >&2
  else
    echo "Restore failed (exit code: ${restore_result}), launching game anyway." >&2
  fi

  # 2. Run Game
  # We run the game directly instead of using 'ludusavi wrap' to avoid issues with
  # Flatpak sandboxing preventing execution of host binaries.
  echo "Debug: Executing game command: $@" >&2
  echo "========================================"
  echo "Launching Game..."
  echo "========================================"

  # Run the command passed as arguments
  # Disable exit-on-error temporarily so we ensure backup runs even if game crashes
  set +e
  "$@"
  exit_code=$?
  set -e

  echo ""
  echo "========================================"
  echo "Game exited with code: ${exit_code}"

  # 3. Backup (uses SKIP_LUDUSAVI flag set during restore if user chose to skip)
  run_ludusavi_op "backup"
  backup_result=$?

  if [[ ${backup_result} -eq 0 ]]; then
    echo "Backup completed!"
  elif [[ ${backup_result} -eq 1 ]]; then
    echo "Backup skipped."
  else
    echo "Backup failed (exit code: ${backup_result})."
  fi
  echo "========================================"
  exit ${exit_code}
fi
