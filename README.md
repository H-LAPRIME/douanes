# Projet Douanes - Intermediaire securise Linux

Douanes est un script Bash qui s'interpose entre un utilisateur et le systeme Linux. Il analyse une commande avant execution, calcule un score de risque, applique des regles de securite, gere les roles utilisateur/admin, journalise les actions et fournit un conseil de securite via IA ou via un conseiller local.

Le projet repond au besoin suivant : eviter qu'une commande dangereuse, accidentelle ou malveillante soit executee sans controle, tout en conservant une trace exploitable dans les logs.

---

## Objectifs

- Controler les commandes avant execution.
- Autoriser les commandes simples et connues.
- Bloquer les commandes dangereuses pour un utilisateur standard.
- Avertir un administrateur et demander confirmation pour les actions critiques.
- Expliquer le score de risque apres chaque commande.
- Fournir une recommandation courte via IA ou conseiller local.
- Journaliser stdout/stderr dans `history.log`.
- Proposer une interface conforme a une commande Linux : `./douanes.sh [options] "commande"`.

---

## Fonctionnement General

1. L'utilisateur lance une commande via `douanes.sh`.
2. Le script detecte le role courant (`user` ou `admin`) depuis `conf/users.conf`.
3. Le moteur T1 analyse la commande :
   - whitelist,
   - blacklist,
   - expressions regulieres dangereuses,
   - score de risque.
4. Douanes affiche :
   - le role,
   - la decision,
   - le score,
   - la justification.
5. Si la commande est risquee, l'IA ou le conseiller local explique le danger et propose une alternative plus sure.
6. T2 execute la commande seulement si elle est autorisee ou confirmee.
7. T3 journalise l'action dans les fichiers de logs.

---

## Structure du Projet

```text
douanes/
|-- douanes.sh                 Script principal et interface CLI
|-- conf/
|   |-- whitelist.conf         Commandes explicitement autorisees
|   |-- blacklist.conf         Commandes interdites
|   `-- users.conf             Roles des utilisateurs
|-- lib/
|   |-- analyze_command.sh     Analyse globale et decision ALLOW/WARN/BLOCK
|   |-- check_lists.sh         Verification whitelist/blacklist
|   |-- regex_patterns.sh      Patterns de commandes dangereuses
|   |-- scoring.sh             Calcul du score de risque
|   |-- subshell_exec.sh       Execution isolee en sous-shell
|   |-- timeout_watcher.sh     Surveillance et timeout
|   |-- execute_secure.sh      Execution securisee selon U1-U5
|   |-- logger_config.sh       Configuration des logs
|   |-- logger.sh              Fonctions log_event et log_audit
|   |-- log_rotation.sh        Rotation, compression et archivage
|   |-- roles.sh               Gestion user/admin
|   |-- admin_handler.sh       Actions admin sensibles
|   |-- llm_advisor.sh         Conseiller IA/local
|   `-- interfaces.sh          Stubs et contrats entre modules
|-- tests/
|   |-- test_t1.sh             Tests analyse/scoring
|   |-- test_t2.sh             Tests execution securisee
|   |-- test_t3.sh             Tests logs/rotation
|   |-- test_t4.sh             Tests roles/admin/IA
|   `-- test_integration.sh    Scenarios leger/moyen/lourd
`-- logs/                      Cree a l'execution, ignore par Git
```

---

## Installation

Sous Linux :

```bash
git clone https://github.com/H-LAPRIME/douanes.git
cd douanes
chmod +x douanes.sh lib/*.sh tests/*.sh
```

Sous Windows, utiliser Git Bash :

```bash
cd /c/Users/pc/Desktop/douanes
```

Le projet fonctionne sans installation systeme. Si `/var/log/douanes` n'est pas accessible, les logs sont ecrits dans `logs/`.

---

## Syntaxe CLI

```bash
./douanes.sh [options] "commande"
```

Le parametre `"commande"` est obligatoire sauf avec `-h` ou `-r`.

### Options

| Option | Description |
|--------|-------------|
| `-h` | Affiche l'aide detaillee du programme |
| `-s` | Execute le traitement Douanes dans un sous-shell |
| `-f` | Execute le traitement dans un processus fils |
| `-t` | Execute le traitement dans un job Bash arriere-plan assimile a un thread |
| `-l <dir>` | Definit le repertoire de journalisation et `history.log` |
| `-r` | Reinitialise les logs, admin uniquement |
| `-a` | Force le mode admin si l'utilisateur est admin dans `conf/users.conf` |
| `-u` | Force le mode user meme si l'utilisateur est admin |

### Exemples

```bash
./douanes.sh -h
./douanes.sh "echo hello"
./douanes.sh -s "echo sous-shell"
./douanes.sh -f "find . -maxdepth 2 -type f"
./douanes.sh -t "grep -R TODO lib"
./douanes.sh -l logs-demo "pwd"
./douanes.sh -u "reboot"
./douanes.sh -a "reboot"
```

---

## Roles User et Admin

Les roles sont definis dans :

```text
conf/users.conf
```

Format :

```text
username:role:hash
```

Exemple :

```text
pc:admin:test
```

### Mode user

Un utilisateur standard peut executer les commandes autorisees :

```bash
./douanes.sh -u "echo hello"
```

Une commande dangereuse est bloquee :

```bash
./douanes.sh -u "reboot"
```

### Mode admin

Un administrateur recoit un avertissement sur les commandes critiques :

```bash
./douanes.sh -a "reboot"
```

Sortie attendue :

```text
[ROLE] Execution en tant que admin
[ANALYSE] Decision : WARN | Score : 10/10
[ADMIN-WARN] Commande critique detectee.
Tapez o pour confirmer, n pour annuler :
```

Le mode admin ne s'active pas automatiquement pour n'importe qui. L'utilisateur doit etre declare admin dans `conf/users.conf`.

---

## Analyse et Score

Chaque commande produit une decision :

| Decision | Signification |
|----------|---------------|
| `ALLOW` | Commande autorisee |
| `WARN` | Commande risquee, confirmation demandee |
| `BLOCK` | Commande interdite |

Le score varie de `0/10` a `10/10`.

Exemple :

```bash
./douanes.sh "chmod 777 /"
```

Sortie :

```text
[ANALYSE] Decision : BLOCK | Score : 10/10
[ANALYSE] Justification : ...
```

Les criteres utilises sont :

- presence dans la blacklist,
- presence dans la whitelist,
- detection regex,
- arguments dangereux,
- chemins systeme sensibles,
- usage de `sudo` ou `su`,
- pipes, redirections et chainages.

---

## Role de l'IA

Le module IA est :

```text
lib/llm_advisor.sh
```

Il ne decide pas et n'execute jamais de commande. Son role est uniquement consultatif :

- expliquer pourquoi une commande est risquee,
- donner une alternative plus sure,
- rappeler une recommandation courte.

Si Mistral est configure dans `.env`, Douanes tente de l'utiliser :

```env
LLM_PROVIDER=mistral
MISTRAL_MODEL=mistral-small-latest
LLM_TIMEOUT=10
```

Si l'API IA est indisponible, Douanes affiche un conseiller local court :

```text
[Conseiller local]
Score : 10/10 (BLOCK)
Danger : peut interrompre les services et le travail en cours.
Alternative sure : verifier avec 'who' ou 'ps aux', puis planifier l'arret.
Recommandation : continuer seulement si la cible est exacte.
```

---

## Journalisation

Douanes gere plusieurs logs :

| Fichier | Role |
|---------|------|
| `douanes.log` | Evenements generaux |
| `security.log` | Blocages et alertes securite |
| `audit.log` | Actions administrateur |
| `history.log` | stdout/stderr au format demande par le sujet |

Le fichier `history.log` suit le format :

```text
yyyy-mm-dd-hh-mm-ss : username : INFOS : message stdout
yyyy-mm-dd-hh-mm-ss : username : ERROR : message stderr
```

Par defaut :

- Linux avec droits : `/var/log/douanes/history.log`
- Git Bash/Windows ou sans droits : `logs/history.log`

Avec un dossier personnalise :

```bash
./douanes.sh -l logs-demo "echo test"
cat logs-demo/history.log
```

---

## Gestion des Erreurs

| Code | Signification |
|------|---------------|
| `100` | Option inexistante |
| `101` | Parametre obligatoire manquant |
| `102` | Echec de traitement ou d'execution |
| `103` | Privileges administrateur requis |
| `2` | Commande bloquee pour raison de securite |
| `255` | Timeout |

Exemples :

```bash
./douanes.sh -z
echo $?
# 100

./douanes.sh
echo $?
# 101

DOUANES_TEST_USER=guest ./douanes.sh -r
echo $?
# 103
```

Apres une erreur d'utilisation, Douanes affiche aussi l'aide detaillee.

---

## Scenarios de Demonstration

Le sujet demande des traitements leger, moyen et lourd, ainsi que les modes subshell, fork et thread.

Lancer :

```bash
bash tests/test_integration.sh
```

Le script couvre :

- traitement leger : `echo`,
- traitement moyen : `find`,
- traitement lourd : `sleep` avec timeout,
- execution en sous-shell `-s`,
- execution par processus fils `-f`,
- execution type thread `-t`,
- blocage d'une commande dangereuse.

---

## Tests Unitaires

```bash
bash tests/test_t1.sh
bash tests/test_t2.sh
bash tests/test_t3.sh
bash tests/test_t4.sh
bash tests/test_integration.sh
```

Etat actuel :

```text
T1 : 28/28
T2 : 19/19
T3 : 33/33
T4 : OK
Integration : OK
```

---

## Conformite au Cahier des Charges

| Exigence | Etat |
|----------|------|
| Script Bash principal | OK |
| Parametre obligatoire | OK |
| Options `-h -f -t -s -l -r` | OK |
| Options admin | OK avec `-r` et `-a` |
| Conditions, boucles, fonctions | OK |
| Variables d'environnement | OK |
| Regex | OK |
| Manipulation fichiers | OK |
| Recherche, archivage, compression | OK |
| Controle d'acces | OK |
| Pipes/filtres | OK |
| stdout/stderr vers terminal et `history.log` | OK |
| Codes d'erreur specifiques | OK |
| Documentation via `-h` | OK |
| Scenarios leger/moyen/lourd | OK |

---

## Securite

- `.env` est ignore par Git.
- `logs/` est ignore par Git.
- Les commandes critiques sont bloquees pour les utilisateurs standards.
- Les actions admin sont journalisees dans `audit.log`.
- Le conseiller IA/local ne peut pas executer de commande.

Important : si une cle API a ete partagee ou affichee, elle doit etre regeneree.
