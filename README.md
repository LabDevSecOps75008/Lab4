# Lab DevSecOps — Sécuriser une image Docker (PHP)

> **Durée estimée : 1h00 – 1h30**
> **Stack : PHP 8 (PHP-FPM) + Nginx + Composer**
> **Scanner : Trivy**

---

## Objectifs pédagogiques

À la fin de ce TP, vous serez capable de :

- Identifier les vulnérabilités d'une image Docker avec un scanner automatique (Trivy).
- **Lire et interpréter** la sortie d'un scan (sévérités, version installée vs version corrigée).
- Distinguer les CVE qui viennent de **l'image de base (OS)** de celles qui viennent de **vos dépendances Composer**.
- Comprendre l'impact concret d'un conteneur mal configuré via une simulation d'attaque.
- Corriger un `Dockerfile` **et** des dépendances pour réduire la surface d'attaque.
- Intégrer Trivy dans une pipeline CI pour bloquer automatiquement les images non conformes.

---

## Prérequis

| Outil | Vérification | Indispensable ? |
|-------|--------------|-----------------|
| Git | `git --version` | oui |
| Docker | `docker --version` | oui |
| Trivy | `trivy --version` | oui (installé par `setup.sh` si absent) |
| PHP / Composer | — | **non** : on les exécute via des conteneurs |

> Pas besoin d'installer PHP ni Composer sur votre poste. On utilise les images officielles `composer` et `php`. Exemple :
> ```bash
> docker run --rm -v "$PWD":/app -w /app composer:2 install
> ```
> `./setup.sh` vérifie Git, Docker et Trivy.

---

## Contexte

Vous êtes développeur·se dans une équipe qui vient de containeriser son API PHP. L'image fonctionne, les tests passent, le déploiement est imminent.

L'équipe sécurité demande à passer l'image au scanner avant la mise en production. Un script de simulation d'attaque est lancé en parallèle pour mesurer l'impact réel. Les résultats sont préoccupants.

Votre mission : **comprendre** ce qui ne va pas, **corriger** l'image, et faire **passer la CI au vert**.

---

## Structure du projet

```
Lab4/
├── public/
│   └── index.php                 ← l'API PHP (front controller)
├── composer.json                 ← dépendances (versions VULNÉRABLES au départ)
├── composer.lock                 ← versions verrouillées (déterministe)
├── Dockerfile                    ← image vulnérable (point de départ)
├── nginx.conf                    ← reverse proxy vers PHP-FPM
├── docker-compose.yml            ← lance PHP-FPM + Nginx ensemble
├── .env                          ← fichier de configuration sensible (secrets)
├── .trivyignore                  ← CVE acceptées sciemment (vide au départ)
├── attack-simulation.sh          ← simulation d'attaque
├── setup.sh                      ← vérification des prérequis
├── solution/
│   ├── Dockerfile                ← image corrigée (à ouvrir APRÈS avoir essayé)
│   └── .dockerignore             ← référence : ce qui ne doit jamais entrer dans l'image
└── .github/
    └── workflows/
        └── security.yml          ← pipeline CI avec Trivy
```

> ⚠️ Le `.env` est volontairement commité **uniquement pour ce TP**, afin de démontrer la fuite de secrets. En conditions réelles, un `.env` ne se commit jamais.

---

## Étape 0 — Mise en place

Vérifiez les outils :

```bash
./setup.sh
```

Installez les dépendances PHP (génère/valide `vendor/`) :

```bash
docker run --rm -v "$PWD":/app -w /app composer:2 install
```

Construisez l'image et lancez l'API (PHP-FPM + Nginx) :

```bash
docker compose up --build -d
```

Vérifiez que l'API répond :

```bash
curl http://localhost:3000/health
# → {"status":"ok","version":"1.0.0"}
```

> L'image que **vous** construisez (service `app`, taguée `vulnerable-api`) est celle que vous allez scanner et corriger. Nginx vient de l'image officielle : ce n'est pas la cible du lab.

---

## Étape 1 — Simulation d'attaque

```bash
./attack-simulation.sh
```

Le script simule ce qu'un attaquant ferait après avoir obtenu une exécution de code dans le conteneur. Il **ne vous dit pas quoi corriger** — c'est votre travail.

Sur l'image de départ, vous obtiendrez (extrait réel) :

```
[1/5] PRIVILEGE CHECK
  uid=0(root) gid=0(root) groups=0(root)
  ⚠  DANGER — le processus tourne en root

[2/5] PRIVILEGE ESCALATION
  ⚠  DANGER — /etc/passwd a été modifié

[3/5] SECRETS EXPOSURE
  -rw-r--r-- 1 root root  184 .env          ← présent dans l'image !
  ⚠  DANGER — fichier .env présent dans l'image

[4/5] ATTACK SURFACE
  ⚠  172 paquets installés dans cette image

[5/5] SECRETS LEAKAGE
  DATABASE_URL=mysql://app:S3cr3t-Pr0d-2026!@prod-db:3306/subscribers
  APP_SECRET=change-me-super-secret-key-12345
  ⚠  DANGER — credentials lisibles depuis l'image
```

**Questions :**
- Sous quel utilisateur tourne le processus ? Quel UID ?
- Pourquoi pouvoir écrire dans `/etc/passwd` est-il dangereux ?
- Quels fichiers présents dans `/app` ne devraient pas s'y trouver ?
- 172 paquets : combien en avez-vous réellement besoin pour faire tourner du PHP ?

---

## Étape 2 — Scanner avec Trivy

```bash
trivy image vulnerable-api
```

Pour ne garder que les sévérités les plus graves :

```bash
trivy image --severity HIGH,CRITICAL vulnerable-api
```

### 2.a — Comment lire la sortie de Trivy

Trivy regroupe les résultats **par cible** (« Target »). Pour cette image, il y en a deux :

```
vulnerable-api (debian 13.2)        ← la cible 1 : les paquets de l'OS (l'image de base)
============================
Total: 2968 (UNKNOWN: 5, LOW: 860, MEDIUM: 1768, HIGH: 318, CRITICAL: 17)

app/composer.lock (composer)        ← la cible 2 : vos dépendances PHP
============================
Total: ... (HIGH: 8, CRITICAL: 2)
```

> 💡 Les chiffres exacts **évoluent dans le temps** : la base d'avis de Trivy est mise à jour en continu. Ne cherchez pas à retrouver « le même nombre » que votre voisin ou que cette doc — concentrez-vous sur **les sévérités et les versions corrigées**.

Chaque ligne du tableau détaillé se lit ainsi :

```
┌───────────────────┬────────────────┬──────────┬────────┬───────────────────┬───────────────┐
│      Library      │ Vulnerability  │ Severity │ Status │ Installed Version │ Fixed Version │
├───────────────────┼────────────────┼──────────┼────────┼───────────────────┼───────────────┤
│ guzzlehttp/guzzle │ CVE-2022-31090 │ HIGH     │ fixed  │ 7.4.0             │ 7.4.5, 6.5.8  │
│ twig/twig         │ CVE-2022-23614 │ CRITICAL │ fixed  │ v3.3.0            │ 2.14.11, 3.3.8│
└───────────────────┴────────────────┴──────────┴────────┴───────────────────┴───────────────┘
```

- **Library** : le paquet concerné (ici une dépendance Composer).
- **Vulnerability** : l'identifiant de la faille (CVE ou avis).
- **Severity** : la gravité (`CRITICAL` > `HIGH` > `MEDIUM` > `LOW`).
- **Status** : `fixed` = un correctif existe ; `affected` / `will_not_fix` = pas (encore) de correctif.
- **Installed Version** : la version actuellement embarquée (vulnérable).
- **Fixed Version** : la version à partir de laquelle la faille est corrigée → **c'est votre cible de mise à jour**.

Lire une CVE = « le paquet **X** en version **installée** est vulnérable à **CVE-…** (gravité **…**) ; corrigé en version **…** ». Pour guzzle ci-dessus : « guzzle 7.4.0 est vulnérable, passez en ≥ 7.4.5 ».

### 2.b — `composer audit` : le même diagnostic, côté dépendances

```bash
docker run --rm -v "$PWD":/app -w /app composer:2 audit
```

Sortie (extrait réel) :

```
Found 22 security vulnerability advisories affecting 2 packages:
| Package           | guzzlehttp/guzzle                                       |
| Severity          | high                                                    |
| CVE               | CVE-2022-31091                                          |
| Title             | Change in port should be considered a change in origin  |
| Affected versions | >=7,<7.4.5|>=4,<6.5.8                                    |
```

`composer audit` ne voit **que** vos dépendances PHP (pas l'OS). C'est complémentaire de Trivy.

**Questions :**
- Combien de CVE `HIGH`/`CRITICAL` viennent de l'**OS** ? Combien de vos **dépendances** ?
- D'où vient la **majorité** des CVE ?
- 💡 La grande majorité ne vient **pas** du code que vous avez écrit. Elle vient de ce que vous avez *embarqué sans le choisir* en faisant `FROM php:8.1-fpm` (l'image Debian « complète »).

---

## Étape 3 — Corriger l'image

Les CVE viennent de **deux sources distinctes** — vous devez corriger les deux.

### 3.a — L'image de base et la configuration (`Dockerfile`)

Quatre problèmes à corriger :

| Problème (image de départ) | Correctif |
|----------------------------|-----------|
| `FROM php:8.1-fpm` (PHP 8.1 EOL en 2026 + Debian complète) | `FROM php:8.3-fpm-alpine` (supporté + minimal) |
| Tourne en **root** (pas de `USER`) | `USER www-data` |
| `COPY . .` embarque le `.env` | Ne copier que `public/` et `vendor/` (multi-stage) |
| `composer install` avec les deps de **dev** | `composer install --no-dev` |

### 3.b — Les dépendances Composer

Mettez à jour les paquets signalés par `composer audit` / Trivy vers leur **Fixed Version** :

```bash
docker run --rm -v "$PWD":/app -w /app composer:2 require \
  "guzzlehttp/guzzle:^7.9" "twig/twig:^3.27" "monolog/monolog:^3.0" \
  --update-with-all-dependencies
```

Vérifiez :

```bash
docker run --rm -v "$PWD":/app -w /app composer:2 audit
# → No security vulnerability advisories found.
```

> 🛈 **Note 2026** : Composer 2.10 **bloque désormais par défaut** l'installation de paquets sous avis de sécurité. Ce lab a dû désactiver ce garde-fou (`config.policy.advisories.block: false` dans `composer.json`) uniquement pour *reproduire* l'état vulnérable. En production, **laissez ce blocage actif** : c'est une protection gratuite.

### 3.c — Reconstruire et re-vérifier

```bash
docker build -f solution/Dockerfile -t secure-api .
./attack-simulation.sh            # adaptez IMAGE=secure-api si besoin
trivy image --severity HIGH,CRITICAL secure-api
```

**Objectif atteint quand :**
- `trivy image --severity HIGH,CRITICAL` affiche `Total: 0`,
- le script d'attaque affiche un **utilisateur non-root**, `BLOQUÉ` sur l'écriture système, et **aucun `.env`**.

Résultat attendu sur l'image corrigée (réel) :

```
secure-api (alpine 3.x)   Total: 0 (HIGH: 0, CRITICAL: 0)
id            : uid=82(www-data) ...        ← non-root
write passwd  : BLOCKED                       ← permission refusée
.env          : __NOTFOUND__                  ← plus de secret embarqué
nb paquets    : 41                            ← contre 172 au départ
```

> Indice si vous êtes bloqué : `solution/Dockerfile` contient la correction commentée ligne par ligne — mais essayez d'abord.

---

## Étape 4 — Intégrer dans la pipeline CI

Le fichier `.github/workflows/security.yml` contient un workflow GitHub Actions **complet et commenté**. Lisez-le : chaque step est expliqué.

Ce qu'il fait :
1. récupère le code (`checkout`),
2. construit l'image Docker,
3. lance Trivy et **fait échouer le job** (`exit-code: 1`) si une CVE `HIGH`/`CRITICAL` **corrigeable** est détectée.

Committez et poussez :

```bash
git add -A
git commit -m "fix: image Docker durcie + deps à jour"
git push
```

Rendez-vous dans l'onglet **Actions** de votre dépôt. Le job **« Scan d'image conteneur (Trivy) »** doit passer au vert **uniquement** si votre image est propre.

**Questions :**
- Qu'est-ce qui déclenche le workflow ? Sur quelle(s) branche(s) ?
- Que se passe-t-il si vous poussez l'image vulnérable d'origine ? Pourquoi est-ce utile dans un workflow réel ?
- Pourquoi `ignore-unfixed: true` ? (indice : à quoi sert de casser la CI pour une CVE qu'on ne peut **pas** corriger ?)

---

## Étape 5 — Ce qu'il faut retenir

| Problème | Impact | Correction |
|----------|--------|------------|
| `FROM php:8.1-fpm` (image complète, EOL 2026) | Des **milliers** de CVE OS embarquées (≈ 2968 ici) | `php:8.3-fpm-alpine` (supporté + minimal) |
| Pas de `USER` — tourne en root | Un attaquant peut modifier les fichiers système | `USER www-data` |
| `COPY . .` sans tri | Le `.env` (secrets) finit dans l'image | Multi-stage : ne copier que `public/` + `vendor/` |
| `composer install` avec deps de dev | Plus de paquets = plus de surface d'attaque | `composer install --no-dev` |
| `guzzle 7.4.0`, `twig 3.3.0` | CVE applicatives `HIGH`/`CRITICAL` | Mettre à jour vers la *Fixed Version* |

> Une image Docker n'est pas juste votre code. C'est votre code **+ l'OS + le runtime + tout ce que vous avez oublié de ne pas embarquer**.

---

## Livrables attendus

- La sortie de `./attack-simulation.sh` sur l'image d'origine.
- La sortie de `trivy image --severity HIGH,CRITICAL vulnerable-api` **avant** correction.
- La sortie de `composer audit` avant et après correction.
- La sortie de `trivy image --severity HIGH,CRITICAL secure-api` **après** correction (`Total: 0`).
- Votre `Dockerfile` corrigé.
- Le pipeline CI au vert sur GitHub Actions.

---

## Pour aller plus loin (optionnel)

- `trivy fs .` : scanner directement `composer.lock` sans construire l'image.
- Générer un SBOM : `trivy image --format cyclonedx --output sbom.json secure-api`.
- Pousser l'image vers un registry (GHCR / Docker Hub) et la scanner depuis le registry.
- Ajouter un upload SARIF dans la CI (`format: sarif`) pour voir les findings dans l'onglet **Security** de GitHub.
