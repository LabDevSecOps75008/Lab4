# Image CORRIGÉE — à comparer avec le Dockerfile de la racine.
# Build depuis la racine du dépôt :
#   docker build -f solution/Dockerfile -t secure-api .
#
# Quatre corrections, une par problème de l'image de départ :
#   1. Base minimale et supportée  : php:8.3-fpm-alpine  (vs php:8.1-fpm Debian).
#   2. Multi-stage                 : Composer n'est PAS dans l'image finale.
#   3. Sans dépendances de dev      : --no-dev exclut phpunit & co.
#   4. Non-root                     : USER www-data.
# (Le .env n'est plus copié : on ne copie QUE public/ et vendor/.)

# ---- Étape 1 : installation des dépendances (image jetable) ----
FROM composer:2 AS build
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --optimize-autoloader --no-interaction

# ---- Étape 2 : image finale, minimale ----
FROM php:8.3-fpm-alpine
WORKDIR /app

# On ne copie que le strict nécessaire à l'exécution.
COPY --from=build /app/vendor ./vendor
COPY public ./public

# www-data (uid 82) existe déjà dans l'image officielle : on tourne sous ce compte.
USER www-data

EXPOSE 9000
CMD ["php-fpm"]
