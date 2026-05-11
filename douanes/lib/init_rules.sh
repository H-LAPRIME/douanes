#!/usr/bin/env bash
# =============================================================================
# init_rules.sh — Initialisation des fichiers de règles de sécurité
# Tâche : T1 | Responsable : Doha
# Dépend de : aucun
# Projet : douanes 
# Tâche   : T1 — Moteur d'Analyse et de Scoring
# Usage   : sudo bash init_rules.sh
# =============================================================================

RULES_DIR="/etc/douanes"
WHITELIST="$RULES_DIR/whitelist.conf"
BLACKLIST="$RULES_DIR/blacklist.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Vérification des privilèges root ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Ce script doit être exécuté en tant que root."
        echo -e "${YELLOW}[HINT]${NC}  Utilisez : sudo bash init_rules.sh"
        exit 1
    fi
}

# --- Création du répertoire de règles ---
create_rules_dir() {
    if [[ ! -d "$RULES_DIR" ]]; then
        mkdir -p "$RULES_DIR"
        chmod 750 "$RULES_DIR"
        echo -e "${GREEN}[INFO]${NC} Répertoire créé : $RULES_DIR"
    else
        echo -e "${YELLOW}[WARN]${NC} Répertoire déjà existant : $RULES_DIR"
    fi
}

# --- Création de la whitelist ---
create_whitelist() {
    cat > "$WHITELIST" << 'EOF'
# =============================================================
# whitelist.conf — Commandes explicitement autorisées
# Format : une commande (base) par ligne
# Les lignes commençant par # sont des commentaires
# =============================================================

# Navigation et affichage
ls
pwd
echo
cat
less
more
clear

# Recherche et filtrage
grep
find
awk
sed
cut
sort
uniq
wc
head
tail

# Informations système
date
whoami
hostname
uname
uptime
df
du
free
top
ps
id

# Réseau (lecture seule)
ping
curl
wget
netstat
ss
ip

# Fichiers (lecture)
file
stat
md5sum
sha256sum
diff
EOF

    chmod 644 "$WHITELIST"
    echo -e "${GREEN}[INFO]${NC} Whitelist créée : $WHITELIST"
}

# --- Création de la blacklist ---
create_blacklist() {
    cat > "$BLACKLIST" << 'EOF'
# =============================================================
# blacklist.conf — Commandes interdites aux utilisateurs standard
# Format : pattern (partiel ou complet) par ligne
# Toute commande contenant ce pattern sera bloquée
# =============================================================

# Suppression destructrice
rm -rf /
rm -rf /*
rm --no-preserve-root

# Écrasement de disque
dd if=/dev/zero
dd if=/dev/random of=/dev/sd
mkfs

# Arrêt système
shutdown
reboot
halt
poweroff
init 0
init 6

# Permissions dangereuses
chmod 777 /
chmod -R 777 /
chown -R root /

# Fork bomb
:(){:|:&};:
:(){ :|: & };:

# Exécution réseau non vérifiée
curl | bash
wget | sh
curl | sh

# Accès root direct
sudo su
sudo -i
sudo bash
sudo sh

# Modification du système
passwd root
userdel root
groupdel root
EOF

    chmod 644 "$BLACKLIST"
    echo -e "${GREEN}[INFO]${NC} Blacklist créée : $BLACKLIST"
}

# --- Fonction principale ---
main() {
    echo "=============================================="
    echo "   DOUANES — Initialisation des règles"
    echo "=============================================="

    check_root
    create_rules_dir
    create_whitelist
    create_blacklist

    echo ""
    echo -e "${GREEN}[OK]${NC} Initialisation terminée avec succès."
    echo -e "${GREEN}[OK]${NC} Règles disponibles dans : $RULES_DIR"
    echo ""
    echo "  Whitelist : $WHITELIST"
    echo "  Blacklist : $BLACKLIST"
    echo "=============================================="
}

main "$@"

