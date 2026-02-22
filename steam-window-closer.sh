#!/bin/bash

# Steam Window Closer pre KDE Plasma 6 (Wayland)

# Kontrola Wayland session
if [ "$XDG_SESSION_TYPE" != "wayland" ]; then
    echo "Tento script funguje len na Wayland session!"
    exit 1
fi

# Kontrola KDE
if [ "$XDG_CURRENT_DESKTOP" != "KDE" ]; then
    echo "Tento script je určený pre KDE Plasma!"
    exit 1
fi

echo "Zatvárám Steam okná v KDE Plasma..."

# Metóda 1: Skús kdotool (ak je nainštalovaný)
if command -v kdotool &> /dev/null; then
    echo "Používam kdotool..."
    steam_windows=$(kdotool search --class "steam" 2>/dev/null)
    
    if [ -z "$steam_windows" ]; then
        echo "Nenašli sa žiadne Steam okná."
        exit 0
    fi
    
    # Pre každé okno pošli close príkaz (simuluje kliknutie na X)
    echo "$steam_windows" | while read -r win_id; do
        kdotool windowclose "$win_id" 2>/dev/null
        echo "Zatvorené okno: $win_id"
    done
    echo "Hotovo!"
    exit 0
fi

# Metóda 2: Skús wmctrl cez XWayland
if command -v wmctrl &> /dev/null; then
    echo "Používam wmctrl..."
    closed=0
    wmctrl -lx 2>/dev/null | grep -i steam | awk '{print $1}' | while read -r win_id; do
        if wmctrl -ic "$win_id" 2>/dev/null; then
            echo "Zatvorené okno: $win_id"
            ((closed++))
        fi
    done
    echo "Hotovo!"
    exit 0
fi

# Metóda 3: Použijeme xdotool cez XWayland
if command -v xdotool &> /dev/null; then
    echo "Používam xdotool..."
    # Najprv získaj všetky Steam okná
    steam_windows=$(xdotool search --class "steam" 2>/dev/null)
    
    if [ -z "$steam_windows" ]; then
        echo "Nenašli sa žiadne Steam okná."
        exit 0
    fi
    
    # Pre každé okno pošli WM_DELETE_WINDOW správu (akoby si klikol na X)
    echo "$steam_windows" | while read -r win_id; do
        # Skús najprv poslať WM_DELETE_WINDOW udalosť
        wmctrl -ic "$win_id" 2>/dev/null || xdotool windowunmap "$win_id" 2>/dev/null
        echo "Zatvorené okno: $win_id"
    done
    echo "Hotovo!"
    exit 0
fi

# Žiadny nástroj nie je dostupný
echo ""
echo "Žiadny podporovaný nástroj nie je nainštalovaný."
echo ""
echo "Nainštaluj jeden z týchto nástrojov:"
echo "  1. kdotool (najlepšie pre KDE Wayland):"
echo "     yay -S kdotool-git"
echo ""
echo "  2. wmctrl (funguje cez XWayland):"
echo "     sudo pacman -S wmctrl"
echo ""
echo "  3. xdotool (funguje cez XWayland):"
echo "     sudo pacman -S xdotool"
echo ""
exit 1
