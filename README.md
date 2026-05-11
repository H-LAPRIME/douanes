# 🛃 Projet Douanes — Intermédiaire Sécurisé Linux

> Script Bash qui s'interpose entre l'utilisateur (ou une IA) et le système Linux :
> analyse, évalue et contrôle chaque commande de manière sécurisée et traçable.

---

## 📁 Structure du projet

```
douanes/
├── douanes.sh              # Script principal (orchestrateur) — Tâche 4
├── lib/
│   ├── interfaces.sh       # Contrats/signatures partagées entre modules
│   ├── analyze_command.sh  # T1 — Fonction principale d'analyse
│   ├── check_lists.sh      # T1 — Whitelist / blacklist
│   ├── regex_patterns.sh   # T1 — Patterns regex dangereux
│   ├── scoring.sh          # T1 — Calcul du score de risque
│   ├── subshell_exec.sh    # T2 — Exécution en sous-shell isolé
│   ├── timeout_watcher.sh  # T2 — Surveillance et kill par timeout
│   ├── execute_secure.sh   # T2 — Gestion des cas U1–U5
│   ├── logger_config.sh    # T3 — Configuration logs
│   ├── logger.sh           # T3 — Fonctions log_event() et log_audit()
│   ├── log_rotation.sh     # T3 — Rotation et archivage
│   ├── roles.sh            # T4 — Gestion des rôles (OWNER: H-LAPRIME)
│   ├── admin_handler.sh    # T4 — Cas admin A1–A5 (OWNER: H-LAPRIME)
│   └── llm_advisor.sh      # T4 — Intégration LLM (OWNER: H-LAPRIME)
├── conf/
│   ├── whitelist.conf      # Commandes autorisées
│   ├── blacklist.conf      # Commandes interdites
│   └── users.conf          # Utilisateurs et rôles (format: user:role:hash)
├── tests/
│   ├── test_t1.sh          # Tests unitaires Tâche 1
│   ├── test_t2.sh          # Tests unitaires Tâche 2
│   ├── test_t3.sh          # Tests unitaires Tâche 3
│   ├── test_t4.sh          # Tests unitaires Tâche 4
│   └── test_integration.sh # Scénario d'intégration global
└── logs/                   # Répertoire des logs (créé à l'exécution)
```

---

## 👥 Répartition des tâches

| Tâche | Titre | Responsable | Branche | Statut |
|-------|-------|-------------|---------|--------|
| T1 | Moteur d'Analyse & Scoring | *(prénom équipier 1)* | `feature/t1-scoring` | 🔲 À faire |
| T2 | Exécution Sécurisée & Surveillance | **khalid** | `feature/t2-exec` | 🔲 À faire |
| T3 | Journalisation & Traçabilité | *(prénom équipier 3)* | `feature/t3-logs` | 🔲 À faire |
| T4 | Gestion des Rôles & LLM | **H-LAPRIME** | `feature/t4-roles` | 🔲 À faire |

---

## 🔗 Interfaces partagées (contrats entre modules)

> Voir [`lib/interfaces.sh`](lib/interfaces.sh) pour les signatures complètes.

### Ce que T4 fournit aux autres tâches

```bash
# Retourne le rôle de l'utilisateur : "admin" ou "user"
get_user_role "username"       # → "admin" | "user"

# Retourne 0 si admin, 1 sinon
is_admin                       # → exit code 0 | 1

# Double confirmation admin (bloque si non-admin)
require_admin_confirmation "action"  # → exit code 0 | 1
```

### Ce que T4 consomme des autres tâches

```bash
# De T1 (analyze_command.sh)
analyze_command "cmd"          # → "ALLOW|0|raison" | "WARN|5|raison" | "BLOCK|10|raison"

# De T3 (logger.sh)
log_event "LEVEL" "cmd" score "detail"
log_audit "action" "detail"
```

### Format de sortie standard

| Fonction | Format retour | Exemple |
|----------|--------------|---------|
| `analyze_command` | `DECISION\|SCORE\|RAISONS` | `BLOCK\|10\|Commande blacklistée` |
| `get_user_role` | string | `admin` |
| `log_event` | void (écrit dans fichier) | — |

---

## ⚙️ Conventions de code

### Nommage des fonctions
- `snake_case` pour toutes les fonctions : `get_user_role()`, `log_event()`
- Préfixe du module : fonctions T1 → `analyze_*`, `check_*`, `score_*`
- Fonctions T3 → `log_*`, `rotate_*`
- Fonctions T4 → `get_user_*`, `is_admin`, `require_admin_*`, `consult_llm`

### En-tête obligatoire de chaque fichier
```bash
#!/usr/bin/env bash
# nom_fichier.sh — Description courte
# Tâche : TX | Responsable : Prénom NOM
# Dépend de : liste des fichiers sourcés
```

### Gestion des erreurs
- Toujours utiliser `set -euo pipefail` dans les scripts principaux
- Retourner des codes d'erreur explicites (0 = succès, 1 = erreur, 2 = sécurité, -1 = timeout)
- Logger **toujours** avant de `return` avec une erreur

### Variables
- `MAJUSCULES` pour les constantes globales et les chemins
- `minuscules` pour les variables locales (utiliser `local`)
- Toujours entre guillemets : `"$variable"` jamais `$variable`

---

## 🚀 Installation et lancement

```bash
# 1. Cloner le repo
git clone https://github.com/H-LAPRIME/douanes.git
cd douanes

# 2. Rendre les scripts exécutables
chmod +x douanes.sh lib/*.sh tests/*.sh

# 3. Initialiser les règles (nécessite sudo)
sudo bash lib/init_rules.sh

# 4. Lancer une commande
./douanes.sh "ls /tmp"
./douanes.sh "echo hello world"

# 5. Lancer les tests
bash tests/test_integration.sh
```

---

## 🧪 Tests attendus

```bash
# T1 — Analyse
analyze_command "ls -la"      # → ALLOW|0|...
analyze_command "rm -rf /"    # → BLOCK|10|...
analyze_command "sudo su -"   # → BLOCK|9|...

# T2 — Exécution
execute_secure "echo OK"      # → affiche OK, code 0
execute_secure "sleep 100"    # → [TIMEOUT] après 30s

# T3 — Logs
log_event "INFO" "test" 0 "msg"   # → entrée dans douanes.log
archive_logs                       # → archive .tar.gz créée

# T4 — Rôles
is_admin                           # → 1 (si user standard)
admin_reset_logs                   # → [ERROR] Accès refusé
```

---

## 🌿 Workflow Git

```bash
# Chaque équipier travaille sur sa branche
git checkout feature/t1-scoring    # (ou t2, t3, t4)

# Commit réguliers avec messages clairs
git commit -m "T1: ajoute check_regex_patterns() avec 10 patterns"

# Quand une étape est terminée → Pull Request vers main
# H-LAPRIME review toutes les PRs avant merge
```

### Règles de commit

| Préfixe | Usage |
|---------|-------|
| `T1:` | Code Tâche 1 |
| `T2:` | Code Tâche 2 |
| `T3:` | Code Tâche 3 |
| `T4:` | Code Tâche 4 |
| `INIT:` | Structure, config, README |
| `FIX:` | Correction de bug |
| `TEST:` | Ajout/modification de tests |
| `DOCS:` | Documentation uniquement |

---

## 📋 Suivi d'avancement (Kanban)

### 🔴 À faire
- [ ] T1 : `init_rules.sh` — initialisation whitelist/blacklist
- [ ] T1 : `check_lists.sh` — fonctions is_whitelisted / is_blacklisted
- [ ] T1 : `regex_patterns.sh` — tableau DANGEROUS_PATTERNS
- [ ] T1 : `scoring.sh` — calculate_risk_score()
- [ ] T1 : `analyze_command.sh` — fonction principale
- [ ] T2 : `subshell_exec.sh` — run_in_subshell()
- [ ] T2 : `timeout_watcher.sh` — watch_process() + get_return_code()
- [ ] T2 : `execute_secure.sh` — cas U1 à U5
- [ ] T3 : `logger_config.sh` — variables et init
- [ ] T3 : `logger.sh` — log_event() et log_audit()
- [ ] T3 : `log_rotation.sh` — rotation et archivage
- [ ] T4 : `roles.sh` — get_user_role() + is_admin() *(H-LAPRIME)*
- [ ] T4 : `admin_handler.sh` — cas A1–A5 *(H-LAPRIME)*
- [ ] T4 : `llm_advisor.sh` — consult_llm() *(H-LAPRIME)*
- [ ] `douanes.sh` — orchestrateur final *(H-LAPRIME)*
- [ ] `tests/test_integration.sh` — scénario complet

### 🟡 En cours
*(déplacer ici quand vous commencez une tâche)*

### 🟢 Terminé
*(déplacer ici quand la PR est mergée)*

---

## ❓ FAQ

**Q: Mon module dépend d'une fonction pas encore codée par un autre ?**
Utilise un stub depuis `lib/interfaces.sh` — il contient des versions minimales de toutes les fonctions.

**Q: J'ai un conflit de merge ?**
Prévenir H-LAPRIME via le canal #douanes — c'est lui qui gère les merges vers `main`.

**Q: Comment tester sans avoir le système complet ?**
Chaque fichier `tests/test_tX.sh` est autonome et mocke les dépendances manquantes.

---

*Projet — Sécurité Linux | Travaux Pratiques*
