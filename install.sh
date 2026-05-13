#!/bin/bash
# =============================================================================
# install.sh — Installation automatique de la commande douanes
# Projet : DOUANES | ENSET Mohammedia
# Compatible : Linux / WSL / Git Bash Windows
# =============================================================================

set -e

PROJET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOUANES_FILE="$PROJET_DIR/douanes.sh"

echo "========================================"
echo "  Installation de la commande douanes"
echo "========================================"
echo ""

if [[ ! -f "$DOUANES_FILE" ]]; then
    echo "[ERROR] douanes.sh introuvable dans $PROJET_DIR"
    exit 1
fi

chmod +x "$DOUANES_FILE"

# Détection Git Bash Windows
if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "win32"* ]]; then
    INSTALL_DIR="$HOME/bin"
    INSTALL_PATH="$INSTALL_DIR/douanes"
    NEED_SUDO=false
else
    INSTALL_DIR="/usr/local/bin"
    INSTALL_PATH="$INSTALL_DIR/douanes"
    NEED_SUDO=true
fi

echo "[INFO] Dossier projet : $PROJET_DIR"
echo "[INFO] Installation dans : $INSTALL_PATH"

mkdir -p "$INSTALL_DIR" 2>/dev/null || true

WRAPPER_CONTENT="#!/bin/bash
CURRENT_DIR=\"\$(pwd)\"
cd \"$PROJET_DIR\" || exit 1
PWD_ORIG=\"\$CURRENT_DIR\" ./douanes.sh \"\$@\""

# Installation selon environnement
if [[ "$NEED_SUDO" == true ]]; then
    if command -v sudo >/dev/null 2>&1; then
        echo "$WRAPPER_CONTENT" | sudo tee "$INSTALL_PATH" >/dev/null
        sudo chmod +x "$INSTALL_PATH"
    else
        echo "[WARN] sudo introuvable. Installation locale dans ~/bin"
        INSTALL_DIR="$HOME/bin"
        INSTALL_PATH="$INSTALL_DIR/douanes"
        mkdir -p "$INSTALL_DIR"
        echo "$WRAPPER_CONTENT" > "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
    fi
else
    mkdir -p "$INSTALL_DIR"
    echo "$WRAPPER_CONTENT" > "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
fi

# Ajouter ~/bin au PATH si installation locale
if [[ "$INSTALL_DIR" == "$HOME/bin" ]]; then
    SHELL_RC="$HOME/.bashrc"

    if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$SHELL_RC" 2>/dev/null; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
        export PATH="$HOME/bin:$PATH"
        echo "[INFO] ~/bin ajouté au PATH dans ~/.bashrc"
    fi
fi

# Vérification
hash -r 2>/dev/null || true

if command -v douanes >/dev/null 2>&1; then
    echo ""
    echo "[OK] Commande 'douanes' installée avec succès !"
    echo "[OK] Tu peux maintenant utiliser :"
    echo ""
    echo "  douanes \"ls -la\""
else
    echo ""
    echo "[WARN] Installation faite, mais le terminal ne trouve pas encore 'douanes'."
    echo "Ferme et rouvre le terminal, ou lance :"
    echo ""
    echo "  source ~/.bashrc"
    echo ""
    echo "Puis teste :"
    echo ""
    echo "  douanes \"ls -la\""
fi