# Ludusavi Universal Wrapper (for mac/Linux)
- windows version is seperate, and i didnt make it as of now

## What does it do

- **Automatic backups** - Your saves are backed up every time you quit a game
- **Auto-restore** - Latest saves restored when you launch a game
- **Cross-device sync** - Play on your laptop, continue on your desktop (with Syncthing)
- **Works everywhere** - Compatible with Heroic, Lutris, and any launcher that supports wrappers, or at least lets you run a command before/after launching a game
- **Zero maintenance** - Set it up once, forget about it, i hope 😇 (this emoji i did add, not the clanker)

## Quick Start

### 1. Install Ludusavi

Pick your platform:

**macOS (Homebrew):**
```bash
brew install ludusavi
```

**Linux (Flatpak):**
```bash
flatpak install com.github.mtkennerly.ludusavi
```

**Linux (Arch):**
```bash
pacman -S ludusavi
```

### 2. Install This Wrapper

```bash
# Download the script
wget https://raw.githubusercontent.com/JustAdreamerFL/ludusavi-wrapper/main/ludusavi_universal_wrapper.sh

# Make it executable
chmod +x ludusavi_universal_wrapper.sh

# Move to your local bin folder
mkdir -p ~/.local/bin
mv ludusavi_universal_wrapper.sh ~/.local/bin/ludusavi-wrapper
```

### 3. Add to Your Game Launcher

**Heroic Launcher:**
1. Go to Settings → Advanced
2. Find "Wrapper" field
3. Enter: `/path/to/ludusavi-wrapper --cache` (if you want caching, more on that later..)

**Lutris:**
1. Right-click a game → Configure
2. Go to System options tab
3. Find "Command prefix" field
4. Enter: `/path/to/ludusavi-wrapper --cache` (if you want caching, more on that later..)

- Your saves will now backup automatically when you play games.

## How It Works

Every time you launch a game:
1. **Restores** your latest save files
2. **Runs** your game normally
3. **Backs up** your saves when you quit

## Sync Across Multiple Computers (Optional)

Want to play on different devices? Add Syncthing for automatic save synchronization.

### What You'll Need

- [Syncthing](https://syncthing.net/downloads/) - Free, open-source file sync
- [stc](https://github.com/tenox7/stc) - Syncthing CLI tool (optional, if you want to verify sync status before restoring saves)

### Setup Steps

1. **Install Syncthing:**
   - macOS: `brew install syncthing`
   - Linux: Follow the [official guide](https://syncthing.net/downloads/#:~:text=syncthing.net.-,Base%20Syncthing,-This%20is%20the)

2. **Configure Syncthing:**
   - Start Syncthing and open http://localhost:8384
   - Create a new folder called `ludusavi_server`
   - Point it to ludusavi's backup directory
   - *Share this folder* with your other devices

3. **Install stc (optional, if you want to verify sync status before restoring saves):**
   ```bash
   go install github.com/tenox7/stc@latest
   ```
 **Configure the stc:**

   Create `~/.config/ludusavi-wrapper/config` with:
   ```
   syncthing_url http://localhost:8384
   api_key YOUR-SYNCTHING-API-KEY
   ```

- Now your saves sync automatically between all your computers

## Usage Examples

### Wrapper Mode
```bash
# Wrap any game executable
ludusavi-wrapper /path/to/game.exe

# With caching for faster startup (recommended)
ludusavi-wrapper --cache /path/to/game.exe

# Override game name detection
ludusavi-wrapper --game-name="The Witcher 3" /path/to/witcher3.exe
```

### Pre/Post Modes

**Backup only**:
```bash
ludusavi-wrapper --mode=post --game-name="My Game"
```

**Restore only**:
```bash
ludusavi-wrapper --mode=pre --game-name="My Game"
```

### Launcher Integration

**Heroic (macOS example):**
```
Wrapper field: /Users/yourname/.local/bin/ludusavi-wrapper --cache
```

**Lutris (Linux example):**
```
Command prefix: /home/yourname/.local/bin/ludusavi-wrapper --cache
```

## Configuration

### Config File Location
`~/.config/ludusavi-wrapper/config`

### Available Options

```bash
# Enable stc integration
syncthing_url http://localhost:8384
api_key YOUR-API-KEY-HERE

# Customize behavior
enable_notifications true          # Show desktop notifications
check_network true                 # Update manifest when online
max_sync_wait 30                   # Max seconds to wait for sync
```

### Command Line Options

```
--cache              Speed up startup by caching tool paths
--mode=MODE          wrapper (default), pre (restore only), post (backup only)
--game-name=NAME     Override automatic game name detection
-h, --help           Show help message
```

## Troubleshooting

### Game name detected incorrectly
Use the `--game-name` option:
```bash
ludusavi-wrapper --game-name="Actual Game Name" /path/to/game
```

### Script can't find ludusavi
The script auto-detects ludusavi from common install locations. If it fails, set the path manually:
```bash
export LUDUSAVI_PATH="/path/to/ludusavi"
```

### Syncthing warnings keep appearing
Check that:
1. Syncthing is running (`ps aux | grep syncthing`)
2. Your API key is correct in the config file
3. The `ludusavi_server` folder is properly synced

### Notifications not showing
The script tries multiple notification methods. Ensure you have one of:
- `osascript` (macOS)
- `notify-send` (Linux)
- `zenity` (Linux fallback)

### Caching Issues
Delete the cache to force re-detection:
```bash
rm -rf ~/.cache/ludusavi-wrapper/
```

## FAQ

**Q: Will this slow down game launches?**
A: Yes, but if you play games through for example Steam, that is what you are already used to.

**Q: Can I use this with Wine/Proton games?**
A: Yes. The wrapper works with any executable.

**Q: Is my data safe?**
A: Your saves are stored locally and backed up by ludusavi. With Syncthing, you control where your data syncs.


## How It Works Technically

### Game Name Detection
The script tries to detect your game name in this order:
1. `--game-name` argument (highest priority)
2. Launcher environment variables (`HEROIC_APP_NAME`, `LUTRIS_GAME_NAME`, etc.)
3. macOS .app bundle name
4. Executable filename
5. Current directory name

### Cache System
When `--cache` is enabled, the script stores:
- ludusavi executable path
- stc executable path
- Best ping command for your OS

Cache is automatically validated each time by checking if paths still exist and are executable.


### (stc) Syncthing Integration
1. Checks network connectivity
2. Updates ludusavi manifest, if you are online
3. Verifies Syncthing sync status before launching
4. Shows a warning if saves aren't fully synced
5. Lets you play anyway (your choice)

## Performance

- **Cold start** (no cache): ~1-2 seconds
- **Warm start** (with cache): ~0.05-0.1 seconds
- **Backup time**: Depends on save file size (usually < 1 second)
- **Restore time**: Depends on save file size (usually < 1 second)
- (i didnt test theese times, it is what the ai slopped)
## Contributing

Found a bug? Have a feature idea? [Open an issue](https://github.com/JustAdreamerFL/ludusavi-wrapper/issues) or submit a pull request!

## Requirements

- **Bash** 3.2+ (included on macOS and Linux)
- **[Ludusavi](https://github.com/mtkennerly/ludusavi)**
- Optional: [Syncthing](https://syncthing.net/) for multi-device sync
- Optional: [stc](https://github.com/tenox7/stc) for sync verification

## Credits

- Built on top of [Ludusavi](https://github.com/mtkennerly/ludusavi) by mtkennerly

## Support

- **Issues**: [GitHub Issues](https://github.com/JustAdreamerFL/ludusavi-wrapper/issues)
- **Discussions**: [GitHub Discussions](https://github.com/JustAdreamerFL/ludusavi-wrapper/discussions)

---
