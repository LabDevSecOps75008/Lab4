# Image de DÉPART — volontairement vulnérable. C'est ce que vous allez corriger.
#
# Problèmes intentionnels (à découvrir avec le scan et la simulation) :
#   - php:8.1-fpm  : PHP 8.1 est en fin de vie en 2026, et l'image Debian
#                    "complète" embarque des centaines de paquets OS.
#   - le conteneur tourne en root (aucune instruction USER).
#   - COPY . .     : copie TOUT le contexte, y compris le fichier .env.
#   - composer install : installe aussi les dépendances de dev (phpunit...).

FROM php:8.1-fpm

# Composer évite d'avorter quand on l'exécute en root (mauvaise pratique assumée ici).
ENV COMPOSER_ALLOW_SUPERUSER=1

WORKDIR /app

# Récupère le binaire Composer depuis l'image officielle.
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY . .

RUN composer install

EXPOSE 9000

CMD ["php-fpm"]
