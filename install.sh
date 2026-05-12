#!/bin/bash
# =============================================================================
# install.sh — Installation automatique de la commande douanes
# Projet : DOUANES | ENSET Mohammedia
# =============================================================================

PROJET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/douanes"

echo "========================================"
echo "  Installation de la commande douanes"
echo "========================================"
echo ""

# Vérifier que douanes.sh existe
if [[ ! -f "$PROJET_DIR/douanes.sh" ]]; then
    echo "[ERROR] douanes.sh introuvable dans $PROJET_DIR"
    exit 1
fi

# Créer le wrapper
echo "[INFO] Création du wrapper dans $INSTALL_PATH ..."
echo "#!/bin/bash
cd $PROJET_DIR && ./douanes.sh \"\$@\"" | sudo tee "$INSTALL_PATH" > /dev/null

# Rendre exécutable
sudo chmod +x "$INSTALL_PATH"

# Vérifier
if command -v douanes &> /dev/null; then
    echo "[OK] Commande 'douanes' installée avec succès !"
    echo "[OK] Tu peux maintenant utiliser 'douanes' depuis n'importe où."
    echo ""
    echo "  Exemple : douanes \"ls -la\""
else
    echo "[ERROR] Installation échouée."
    exit 1
fi
