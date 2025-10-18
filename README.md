# Ludusavi Universal Wrapper

A universal wrapper script for automatic game save backup and restore using [Ludusavi](https://github.com/mtkennerly/ludusavi).

## Features

- **Multi-launcher support**: Works with Lutris, Heroic, and other game launchers
- **Auto-detection**: Automatically detects ludusavi installation (native or Flatpak)
- **Three modes**: 
  - `wrapper` (default): Wraps game execution with pre/post backup
  - `pre`: Pre-launch save restoration only
  - `post`: Post-launch save backup only
- **Smart game name detection**: Automatically detects game names from environment variables or directory structure
- **Caching**: Caches ludusavi path and ping command for fast execution
- **Network detection**: Automatically checks for internet connectivity and updates manifest when available

## Requirements

- Bash
- [Ludusavi](https://github.com/mtkennerly/ludusavi) (native or Flatpak)
- A game launcher (Lutris, Heroic, etc.)

## Installation

1. Download the script:
```bash
wget https://raw.githubusercontent.com/JustAdreamerFL/ludusavi-wrapper/main/ludusavi_universal_wrapper.sh
chmod +x ludusavi_universal_wrapper.sh
```

2. Move it to a convenient location:
```bash
mv ludusavi_universal_wrapper.sh ~/.local/bin/
# or
mv ludusavi_universal_wrapper.sh ~/Documents/code/scripts/
```

## Usage

### As a Wrapper (Default Mode)

Use the script as the game executable in your launcher, with the actual game executable as arguments:

```bash
/path/to/ludusavi_universal_wrapper.sh /path/to/game/executable [game args]
```

### With Lutris (Pre/Post Scripts)

In Lutris, add to your game configuration or global settings:

**Pre-launch script:**
```bash
/path/to/ludusavi_universal_wrapper.sh --mode=pre
```

**Post-exit script:**
```bash
/path/to/ludusavi_universal_wrapper.sh --mode=post
```

### Manual Game Name Override

If automatic detection doesn't work:
```bash
/path/to/ludusavi_universal_wrapper.sh --mode=pre --game-name="MyGame"
```

## Configuration

The script auto-detects ludusavi, but you can override with an environment variable:

```bash
export LUDUSAVI_PATH="/custom/path/to/ludusavi"
```

Or for Flatpak:
```bash
export LUDUSAVI_PATH="flatpak run com.github.mtkennerly.ludusavi"
```

## How It Works

1. **Ludusavi Detection**: Searches common install locations or detects Flatpak installation
2. **Game Name Detection**: 
   - Checks launcher environment variables (`LUTRIS_GAME_NAME`, `HEROIC_GAMES_LAUNCHER_GAME_TITLE`, etc.)
   - Falls back to working directory name (skipping common subdirs like `bin`, `x64`)
   - Can be manually specified with `--game-name=`
3. **Network Check**: Pings 8.8.8.8 to determine if manifest should be updated
4. **Caching**: Stores detected paths in `~/.cache/` for fast subsequent runs

## Troubleshooting

### Script doesn't find ludusavi
- Ensure ludusavi is installed
- Set `LUDUSAVI_PATH` environment variable
- Check cache file: `~/.cache/ludusavi_wrapper_path`

### Wrong game name detected
- Use `--game-name="CorrectName"` argument
- Check debug log: `/tmp/ludusavi_wrapper_debug.log`

### Flatpak permissions
If using Flatpak ludusavi with games in non-standard locations, you may need to grant additional permissions:

```bash
flatpak override --user --filesystem=/path/to/games com.github.mtkennerly.ludusavi
```

### Files with diacritics fail
Ludusavi may have issues with non-ASCII characters in filenames. Consider renaming save files to use ASCII characters only.

## Examples

### Lutris Global Pre/Post Scripts
1. Go to Preferences → Global options
2. Set Pre-launch script: `/home/username/Documents/code/scripts/ludusavi_universal_wrapper.sh --mode=pre`
3. Set Post-exit script: `/home/username/Documents/code/scripts/ludusavi_universal_wrapper.sh --mode=post`
4. Enable "Wait for pre-launch script completion"

### Heroic Game Wrapper
1. Go to game settings
2. Set executable to: `/path/to/ludusavi_universal_wrapper.sh`
3. Set arguments to: `/actual/game/executable`

## Cache Files

The script creates cache files in `~/.cache/`:
- `ludusavi_wrapper_path`: Cached ludusavi executable path
- `ludusavi_wrapper_ping_cmd`: Cached ping command for network detection

To reset cache:
```bash
rm ~/.cache/ludusavi_wrapper_*
```

## License

MIT License - feel free to modify and distribute.

## Credits

- [Ludusavi](https://github.com/mtkennerly/ludusavi) by mtkennerly
- Script developed with assistance from GitHub Copilot
