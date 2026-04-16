#!/bin/bash

DOTFILES="$HOME/dotfiles"

echo "Installing dotfiles..."

# Helper to create symlink
link() {
    local src="$DOTFILES/$1"
    local dest="$2"

    # Create parent directory if needed
    mkdir -p "$(dirname "$dest")"

    # Remove existing file/symlink
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        rm "$dest"
    fi

    ln -s "$src" "$dest"
    echo "  linked $dest -> $src"
}

# Waybar
link "waybar/config.jsonc"        "$HOME/.config/waybar/config.jsonc"
link "waybar/style.css"           "$HOME/.config/waybar/style.css"

# Hyprland
link "hypr/hyprland.conf"         "$HOME/.config/hypr/hyprland.conf"
link "hypr/hypridle.conf"         "$HOME/.config/hypr/hypridle.conf"
link "hypr/hyprlock.conf"         "$HOME/.config/hypr/hyprlock.conf"
link "hypr/hyprpaper.conf"        "$HOME/.config/hypr/hyprpaper.conf"

# Kitty
link "kitty/kitty.conf"           "$HOME/.config/kitty/kitty.conf"

# Zsh
link "zsh/.zshrc"                 "$HOME/.zshrc"
link "zsh/.p10k.zsh"              "$HOME/.p10k.zsh"

# Claude
link "claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

echo ""
echo "Done! Reload Hyprland with: hyprctl reload"
