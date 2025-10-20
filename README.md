# Ludusavi Universal Wrapper

A wrapper script for automatic game save backup and restore using [Ludusavi](https://github.com/mtkennerly/ludusavi).

Basically, if you use this with Syncthing, you get your own Steam Cloud Saves that works with any game. Pretty neat.

**Tested on:** Linux and macOS (should work on both, but your mileage may vary)

## What it does

- Works with Lutris, Heroic Launcher, and probably other launchers too
- Automatically finds ludusavi wherever you installed it (Homebrew, Flatpak, Cargo, etc.)
- If you have Syncthing set up, it'll check if your saves are synced before launching
- Shows a GUI warning if Syncthing isn't done syncing yet
- Three modes:
  - `wrapper` (default): Restores saves → Runs game → Backs up saves
  - `pre`: Just restore saves
  - `post`: Just backup saves
- Tries to figure out the game name automatically from your launcher
- Caches stuff so it starts up fast
- Checks if you're online and updates the ludusavi manifest if you are

## What you need

### The essentials

- **Bash** (you already have this)
- **[Ludusavi](https://github.com/mtkennerly/ludusavi)** - The actual backup tool
  - Get it from: Homebrew, Flatpak, Cargo, or whatever
- A game launcher that lets you wrap executables (Lutris, Heroic, etc.)

### Optional stuff (for syncing saves between computers)

- **[Syncthing](https://syncthing.net/)** - Syncs your saves across devices
- **[stc](https://github.com/tenox7/stc)** - CLI tool for Syncthing (so the script can check sync status)
  - Install with: `go install github.com/tenox7/stc@latest`

## Setting it up

### 1. Get ludusavi

Pick whichever method works for you:

**macOS (Homebrew):**

```bash
brew install ludusavi
```

**Linux (Flatpak):**

```bash
flatpak install com.github.mtkennerly.ludusavi
```

**Linux/macOS (Cargo):**

```bash
cargo install ludusavi
```

### 2. Install this script

```bash
# Grab it
wget https://raw.githubusercontent.com/JustAdreamerFL/ludusavi-wrapper/main/ludusavi_universal_wrapper.sh

# Make it executable
chmod +x ludusavi_universal_wrapper.sh

# Put it somewhere convenient
mkdir -p ~/.local/bin
mv ludusavi_universal_wrapper.sh ~/.local/bin/ludusavi-wrapper
```

### 3. (Optional) Set up Syncthing for multi-device sync

Only do this if you want to sync saves between computers:

**Get Syncthing:**

- macOS: `brew install syncthing`
- Linux: Check [their website](https://syncthing.net/downloads/)

**Get stc (Syncthing CLI):**

```bash
go install github.com/tenox7/stc@latest
```

**Set up the folder:**

1. Start Syncthing and open the web UI (usually http://localhost:8384)
2. Make a folder called `ludusavi_server`
3. Point it to wherever ludusavi saves your backups
4. Share it with your other computers
5. Set up stc to talk to Syncthing

## Configure ludusavi

Just make sure ludusavi knows where to save backups (preferably somewhere Syncthing can sync):

```bash
# Run it once to set things up
ludusavi backup --preview

# Or use the GUI
ludusavi
```

## Quick test

Make sure the script can find ludusavi:

```bash
~/.local/bin/ludusavi-wrapper --help
```

Should show ludusavi getting detected automatically.

## How to use it

### With Heroic Launcher

1. Open Heroic
2. Go to game settings
3. Find the "Wrapper" or "Run with" option in Advanced/Other settings
4. Put: `~/.local/bin/ludusavi-wrapper`
5. That's it, your saves get backed up automatically now

### With Lutris

**Easy way (wrapper):**

1. Open Lutris
2. Right-click game → Configure
3. System options tab
4. "Command prefix" field → enter: `~/.local/bin/ludusavi-wrapper`
5. Done

**Alternative way (pre/post scripts):**

1. Right-click game → Configure
2. System options tab
3. Pre-launch script: `~/.local/bin/ludusavi-wrapper --mode=pre`
4. Post-exit script: `~/.local/bin/ludusavi-wrapper --mode=post`
5. Save

### Running manually

**Normal mode (does everything):**

```bash
ludusavi-wrapper /path/to/game/executable [game args]
```

**Just restore saves:**

```bash
ludusavi-wrapper --mode=pre --game-name="GameName"
```

**Just backup saves:**

```bash
ludusavi-wrapper --mode=post --game-name="GameName"
```

### If the game name gets detected wrong

Just tell it what the name should be:

```bash
ludusavi-wrapper --game-name="Actual Game Name" /path/to/game
```

## Configuration stuff

### Environment variables you can set

The script finds stuff automatically, but you can override if needed:

**Custom ludusavi path:**

```bash
export LUDUSAVI_PATH="/some/custom/path/to/ludusavi"
```

**If using Flatpak:**

```bash
export LUDUSAVI_PATH="flatpak run com.github.mtkennerly.ludusavi"
```

**Force a specific launcher type:**

```bash
export LAUNCHER_TYPE="heroic"  # or "lutris" or "auto"
```

### Where stuff gets cached

The script remembers where it found tools so it starts faster next time:

- **Linux**: `~/.cache/ludusavi_wrapper_path` and `ludusavi_wrapper_ping_cmd`
- **macOS**: `~/Library/Caches/ludusavi-wrapper/`

If you move/reinstall stuff, clear the cache:

```bash
rm -rf ~/.cache/ludusavi_wrapper_*
# or on macOS:
rm -rf ~/Library/Caches/ludusavi-wrapper/
```

## How it works (if you're curious)

### What happens when you launch a game

1. **Finding tools**

   - Looks for ludusavi in common spots (Homebrew, Flatpak, Cargo, etc.)
   - Same for stc if you have Syncthing set up
   - Uses cached paths if it found them before

2. **Figuring out the game name**

   - First checks if you told it explicitly (`--game-name=`)
   - Then looks at launcher variables (Lutris and Heroic set these)
   - On macOS, tries to extract from .app bundles
   - Falls back to the executable name
   - Last resort: uses the directory name (skipping stuff like `bin`, `x64`, etc.)

3. **Syncthing check** (if you have stc installed)

   - Asks Syncthing if the `ludusavi_server` folder is synced
   - Shows you a GUI warning if it's not at 100%
   - Doesn't actually stop you from playing though

4. **Network check**

   - Quick pings to a few DNS servers (Cloudflare, Google, Quad9)
   - Auto-detects the right ping flags for your system
   - Tells ludusavi whether to update its game database

5. **Actually running the game**

   - **Wrapper mode**: Restores saves → Runs your game → Backs up saves
   - **Pre mode**: Just restores saves
   - **Post mode**: Just backs up saves

6. **Cleanup**
   - Tells Syncthing to rescan (if stc is available)
   - Exits with whatever code your game exited with

## If stuff breaks

### Script doesn't find ludusavi

**Check if it's installed:**

```bash
which ludusavi
# or
ludusavi --version
```

**Tell the script where it is:**

```bash
export LUDUSAVI_PATH="/opt/homebrew/bin/ludusavi"
ludusavi-wrapper /path/to/game
```

**Clear the cache:**

```bash
rm ~/.cache/ludusavi_wrapper_path
```

### Script doesn't find stc (Syncthing CLI)

**Check if it's there:**

```bash
which stc
# or
ls ~/go/bin/stc
```

**Add to PATH (if it's in ~/go/bin):**

```bash
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.bashrc
# or for zsh:
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.zshrc
```

The script will auto-detect stc even if it's not in PATH (checks common spots).

### Wrong game name detected

**Option 1: Just tell it:**

```bash
ludusavi-wrapper --game-name="Correct Game Name" /path/to/game
```

**Option 2: Check what it's doing:**

```bash
tail -20 /tmp/ludusavi_wrapper_debug.log
```

### Syncthing warnings keep popping up

If the `ludusavi_server` folder won't sync:

1. Check Syncthing web UI: http://localhost:8384
2. Make sure the folder path matches ludusavi's backup directory
3. Look for sync errors in Syncthing logs
4. Try rescanning manually: `stc rescan ludusavi_server`

### GUI notification not showing

The script tries multiple GUI tools:

- **macOS**: osascript (already installed)
- **Linux**: notify-send, zenity, or kdialog

Install one if you don't have any:

```bash
# Ubuntu/Debian
sudo apt install libnotify-bin zenity

# Fedora
sudo dnf install libnotify zenity

# Arch
sudo pacman -S libnotify zenity
```

### Flatpak permissions

If you're using Flatpak ludusavi and games are in weird places:

```bash
flatpak override --user --filesystem=/path/to/games com.github.mtkennerly.ludusavi
flatpak override --user --filesystem=xdg-data/ludusavi-backup com.github.mtkennerly.ludusavi
```

### Network check is slow

The script uses fast timeouts (300ms on macOS, 1s on Linux). If it's still slow:

**Just disable manifest updates:**

```bash
# Edit the script and change this line:
MANIFEST_UPDATE_FLAG="--no-manifest-update"
```

Or run ludusavi manually to update manifests periodically.

## Extra stuff for multi-device sync

### Syncing saves between computers with Syncthing

If you want your saves on multiple machines:

**1. Install Syncthing everywhere**

```bash
# macOS
brew install syncthing

# Linux (check your distro's docs)
# See: https://syncthing.net/downloads/
```

**2. Set up the Syncthing folder**

1. Start Syncthing: `syncthing` (or use your system's service)
2. Open the web UI: http://localhost:8384
3. Add a folder:
   - **Folder Label**: `ludusavi_server`
   - **Folder Path**: Where ludusavi saves stuff (like `~/ludusavi-backup`)
4. Share it with your other devices
5. Do the same on all your machines

**3. Install stc so the script can check sync status**

```bash
go install github.com/tenox7/stc@latest

# Make sure it works
stc status ludusavi_server
```

**4. Configure stc**

Create `~/.stc/config.yaml`:

```yaml
syncthing_url: http://localhost:8384
api_key: YOUR-API-KEY-HERE
```

Get your API key from Syncthing web UI: Settings → General → API Key

Now the wrapper will:

- Check if everything's synced before launching games
- Warn you if stuff's out of sync
- Tell Syncthing to rescan after backups

### Testing if it all works

**Test ludusavi detection:**

```bash
ludusavi-wrapper --mode=pre --game-name="Test"
```

**Test Syncthing:**

```bash
stc status ludusavi_server
# Should show you the sync percentage
```

**Test the whole thing:**

```bash
# Make a fake game script
echo '#!/bin/bash
echo "Game running..."
sleep 2
echo "Game exiting..."' > /tmp/test_game.sh

chmod +x /tmp/test_game.sh

# Run it through the wrapper
ludusavi-wrapper /tmp/test_game.sh
```

### Making it faster

**The script already caches stuff:**
First run is slower while it figures out where everything is. After that it's faster.

**Skip network checks:**
If you don't want manifest updates, edit the script:

```bash
MANIFEST_UPDATE_FLAG="--no-manifest-update"
```

**Make Syncthing checks faster:**
Edit the `fast_online_check` function in the script to ping fewer DNS servers.

## Examples

### Heroic Launcher (macOS)

1. Open Heroic
2. Pick a game → Settings (gear icon)
3. Scroll down to "Advanced Options"
4. In the "Wrapper" field, put:
   ```
   /Users/yourusername/.local/bin/ludusavi-wrapper
   ```
5. Save and launch

The wrapper figures out the game name automatically from Heroic.

### Lutris (Linux) - For all games

Set it up once:

1. Open Lutris → Preferences (hamburger menu)
2. "Global options" tab
3. Under "System options":
   - **Command prefix**: `~/.local/bin/ludusavi-wrapper`
4. Save

Done. All games now backup/restore automatically.

### Lutris - Per-game scripts

If you want more control:

1. Right-click game → Configure
2. "System options" tab
3. Set:
   - **Pre-launch script**: `/home/username/.local/bin/ludusavi-wrapper --mode=pre --game-name="Exact Game Name"`
   - **Post-exit script**: `/home/username/.local/bin/ludusavi-wrapper --mode=post --game-name="Exact Game Name"`
4. Enable "Wait for pre-launch script completion"
5. Save

### Just running it manually

**Backup a game:**

```bash
ludusavi-wrapper --mode=post --game-name="Factorio"
```

**Restore before playing:**

```bash
ludusavi-wrapper --mode=pre --game-name="Factorio"
```

**Full wrapper with custom game:**

```bash
ludusavi-wrapper --game-name="Custom Game" /path/to/game/executable --game-arg1 --game-arg2
```

## FAQ

### Do I need Syncthing?

Nope! It's totally optional. The script works fine without it for local backups. Syncthing just syncs your saves between computers.

### Will this work with Steam games?

Yep! Use Steam's "Launch Options":

```
/path/to/ludusavi-wrapper %command%
```

### Can I use this with Wine/Proton games?

Sure! It works with any executable, including Wine/Proton through Lutris or Heroic.

### Does this slow down game launches?

Not really:

- First run: ~1-2 seconds (figuring out where stuff is)
- After that: ~100-500ms (reading from cache + quick network check)
- Save restore/backup time depends on how big your saves are

### What if I have multiple game launchers?

The script works with all of them at once. Just set it up in each launcher.

### Can I see what's being backed up?

Yeah! Run ludusavi directly:

```bash
ludusavi backup --preview
```

Or check the debug log:

```bash
tail -f /tmp/ludusavi_wrapper_debug.log
```

### How do I backup/restore manually?

Use pre/post modes:

```bash
# Backup
ludusavi-wrapper --mode=post --game-name="GameName"

# Restore
ludusavi-wrapper --mode=pre --game-name="GameName"
```

## Technical stuff

### Cache files

**Where they are:**

- Linux: `~/.cache/ludusavi_wrapper_path` and `ludusavi_wrapper_ping_cmd`
- macOS: `~/Library/Caches/ludusavi-wrapper/`

**What they store:**

- `ludusavi_wrapper_path`: Where ludusavi is installed
- `ludusavi_wrapper_ping_cmd`: The ping command that works on your system

**Reset if needed:**

```bash
# Linux
rm -f ~/.cache/ludusavi_wrapper_*

# macOS
rm -rf ~/Library/Caches/ludusavi-wrapper/
```

### Debug logging

Everything gets logged to `/tmp/ludusavi_wrapper_debug.log`:

```bash
# See recent stuff
tail -50 /tmp/ludusavi_wrapper_debug.log

# Watch it live
tail -f /tmp/ludusavi_wrapper_debug.log
```

### Environment variables it looks for

**Lutris:**

- `LUTRIS_GAME_NAME`
- `LUTRIS_GAME_ID`

**Heroic:**

- `HEROIC_GAMES_LAUNCHER_GAME_TITLE`
- `HEROIC_APP_NAME`

**Custom:**

- `LUDUSAVI_PATH` - Tell it where ludusavi is
- `LAUNCHER_TYPE` - Force which launcher (`lutris`, `heroic`, `auto`)

## Contributing

If you want to improve this, go for it! Just:

1. Fork it
2. Make your changes
3. Test on Linux and macOS if you can
4. Submit a pull request

**Ideas for improvements:**

- Support for more launchers
- More GUI notification tools
- Better game name detection
- Making it faster

## License

MIT License - do whatever you want with it.

## Credits

- [Ludusavi](https://github.com/mtkennerly/ludusavi) by mtkennerly - The actual save backup tool this wraps
- [Syncthing](https://syncthing.net/) - For syncing files between computers
- [stc](https://github.com/tenox7/stc) by tenox7 - Syncthing CLI tool
- Script made by [@JustAdreamerFL](https://github.com/JustAdreamerFL)

## Support

- **Issues**: [GitHub Issues](https://github.com/JustAdreamerFL/ludusavi-wrapper/issues)
- **Ludusavi docs**: [github.com/mtkennerly/ludusavi](https://github.com/mtkennerly/ludusavi)
- **Syncthing docs**: [docs.syncthing.net](https://docs.syncthing.net/)

---

⭐ Star this if it helped you out!
