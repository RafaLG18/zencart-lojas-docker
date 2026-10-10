FROM php:8.2-apache

ARG ZC_VERSION=2.1.0
ARG ADMIN_DIR=manage

RUN apt-get update && apt-get install -y --no-install-recommends \
        libzip-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev libicu-dev curl mariadb-client \
        openssh-server \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" mysqli pdo_mysql gd zip intl bcmath opcache \
    && a2enmod rewrite \
    && echo "ServerName localhost" > /etc/apache2/conf-enabled/servername.conf \
    && echo "umask 002" >> /etc/apache2/envvars \
    && rm -f /etc/ssh/ssh_host_* \
    && mkdir -p /run/sshd \
    && rm -rf /var/lib/apt/lists/*

# A chave de host SSH não fica na imagem: vem de ssh/ (gerada no host) e é copiada no entrypoint
COPY php.ini /usr/local/etc/php/conf.d/zencart.ini
COPY auth.conf /etc/apache2/conf-enabled/zc-auth.conf
COPY mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf
COPY sshd_config /etc/ssh/sshd_config
COPY zc-entrypoint.sh zc-admin.php zc-cota.sh limites /usr/local/bin/
COPY zc-configure.php /tmp/
RUN chmod +x /usr/local/bin/zc-entrypoint.sh /usr/local/bin/zc-cota.sh /usr/local/bin/limites \
    && echo '[ -n "$PS1" ] && limites' > /etc/profile.d/zz-limites.sh

# Loja pré-instalada: SQL guardado fora do docroot, configure.php lendo o ambiente,
# admin renomeado e instalador removido (o admin bloqueia se algum dos dois faltar)
RUN curl -fsSL "https://github.com/zencart/zencart/archive/refs/tags/v${ZC_VERSION}.tar.gz" \
      | tar xz --strip-components=1 -C /var/www/html \
    && cd /var/www/html \
    && mkdir -p /usr/local/share/zencart/sql \
    && cp zc_install/sql/install/mysql_zencart.sql zc_install/sql/install/mysql_utf8.sql /usr/local/share/zencart/sql/ \
    && mv admin "$ADMIN_DIR" \
    && php /tmp/zc-configure.php /var/www/html "$ADMIN_DIR" \
    && rm -rf zc_install /tmp/zc-configure.php \
    && chown -R www-data:www-data /var/www/html

ENTRYPOINT ["zc-entrypoint.sh"]
CMD ["apache2-foreground"]
