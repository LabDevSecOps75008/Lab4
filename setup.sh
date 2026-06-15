#!/usr/bin/env bash
set -euo pipefail

# Vérifie les prérequis du lab. PHP et Composer ne sont PAS requis en local :
# on les exécute via des conteneurs (images officielles composer / php).

install_trivy() {
    echo "==> Installation de Trivy..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
        | sh -s -- -b /usr/local/bin
}

echo "==> Vérification des prérequis..."
echo ""

ok=0

# Git
if command -v git &>/dev/null; then
    echo "[OK] Git    : $(git --version)"
else
    echo "[MANQUE] Git : installez Git avant de continuer."; ok=1
fi

# Docker (indispensable : build d'image, exécution de PHP/Composer en conteneur)
if command -v docker &>/dev/null; then
    echo "[OK] Docker : $(docker --version)"
else
    echo "[MANQUE] Docker : installez Docker avant de continuer."; ok=1
fi

# Trivy (le scanner ; on propose de l'installer s'il manque)
if command -v trivy &>/dev/null; then
    echo "[OK] Trivy  : $(trivy --version | head -n1)"
else
    echo "[INFO] Trivy absent."
    read -r -p "      L'installer maintenant ? [y/N] " ans
    if [[ "${ans:-N}" =~ ^[yY]$ ]]; then
        install_trivy
        echo "[OK] Trivy  : $(trivy --version | head -n1)"
    else
        echo "      → installez-le plus tard : https://trivy.dev/latest/getting-started/installation/"
        ok=1
    fi
fi

echo ""
echo "Rappel : PHP et Composer ne sont pas nécessaires en local."
echo "  composer install  →  docker run --rm -v \"\$PWD\":/app -w /app composer:2 install"
echo ""

if [[ "$ok" -eq 0 ]]; then
    echo "Tout est en place. Vous pouvez démarrer le TP."
else
    echo "Des prérequis manquent (voir ci-dessus) avant de démarrer."
    exit 1
fi
