FROM php:8.3-apache

RUN docker-php-ext-install pdo pdo_mysql

COPY apache-fallback.conf /etc/apache2/conf-enabled/fallback.conf
COPY public /var/www/html
