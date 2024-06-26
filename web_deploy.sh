#!/bin/bash
clear

## nginx-exporter : 9113
## phpfpm-exporter : 9253

export DISTRIB_CODENAME=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d\= -f2)
export DISRIB_ARCH=$(uname -p)
export DEBIAN_FRONTEND=noninteractive
export SCRIPT_DIR_NAME=$(dirname "$(readlink -f "$0")")
export PHP_VERSIONS=(7.4 8.0 8.1 8.2)
export DEFAULT_PHP_VERSION="8.2"
export HOSTNAME=$(cat /etc/hostname)
export SHORT_HOSTNAME=$(hostname -s)
case $DISTRIB_ARCH in 
    x86_64)
        export DISRIB_ARCH="amd64"
        ;;
    *)
        ;;
esac

function check_status {
    case $1 in
        0)
            echo " -> Success - $2"
            ;;
        *)
            echo " -> Error - $2"
            ;;
    esac
}

function update_script {
    cd ${SCRIPT_DIR_NAME} && git pull
    exit 0
}

function init_server {
    echo "## Starting initialization"
    mkdir -p ~/.local/bin
    echo $(git ls-remote https://github.com/bilyboy785/public/ refs/heads/main | awk '{print $1}') > /root/.web_deploy_latest
    
    echo "# Updating system"
    DEBIAN_FRONTEND=noninteractive apt update -qq > /dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt upgrade -yqq > /dev/null 2>&1
    echo "# Installing base packages"
    DEBIAN_FRONTEND=noninteractive apt install -yqq git zsh curl clamav clamav-daemon wget htop python3 python3-msgpack webp imagemagick libfuse-dev fuse pkg-config libacl1-dev bat software-properties-common pkg-config libattr1-dev libssl-dev liblz4-dev ripgrep fail2ban python3-venv python3-pip proftpd mariadb-client mariadb-server docker.io redis-server > /dev/null 2>&1
    curl -sL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o $HOME/.local/bin/yq && chmod +x $HOME/.local/bin/yq
    curl -sL "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" -o $HOME/.local/bin/jq && chmod +x $HOME/.local/bin/jq

    # if [[ ! -f /root/.local/bin/bat ]]; then
    #     ln -s /usr/bin/batcat ~/.local/bin/bat
    # fi

    echo "# Server Tuning"
    if [[ ! -f /opt/.servertuning ]]; then
        echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
        echo 'vm.swappiness = 1' >> /etc/sysctl.conf
        echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
        echo "servertuning" > /opt/.servertuning
    fi

    echo "# Redis-Server Tuning"
    sed -i 's/^#\ maxmemory-policy\ .*/maxmemory-policy\ allkeys-lru/g' /etc/redis/redis.conf
    sed -i 's/^#\ maxmemory\ .*/maxmemory\ 2g/g' /etc/redis/redis.conf
    sed -i 's/^tcp-keepalive\ .*/tcp-keepalive\ 0/g' /etc/redis/redis.conf
    sed -i 's/^#\ maxclients\ .*/maxclients\ 1000/g' /etc/redis/redis.conf

    echo "# Setting up cron"
    echo '0 6 * * * root PATH=$PATH:/usr/bin:/usr/local/bin /root/.local/bin/certbot renew --post-hook "systemctl reload nginx"' > /etc/cron.d/certbot
    chmod +x /etc/cron.d/certbot
    echo '0 */12 * * * root PATH=$PATH:/usr/bin:/usr/local/bin /root/.local/bin/borgmatic --verbosity -1 --syslog-verbosity 1' > /etc/cron.d/borgmatic
    chmod +x /etc/cron.d/borgmatic

    systemctl restart clamav-daemon.service > /dev/null 2>&1

    systemctl restart redis-server.service > /dev/null 2>&1

    echo "# Installation de Docker-compose"
    curl -SL https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose > /dev/null 2>&1
    chmod +x /usr/local/bin/docker-compose > /dev/null 2>&1

    echo "# Installation de dynamotd"
    curl -L https://github.com/gdubicki/dynamotd/releases/latest/download/dynamotd-linux-amd64 -o /usr/local/bin/dynamotd
    chmod +x /usr/local/bin/dynamotd
    wget -q https://raw.githubusercontent.com/dylanaraps/pfetch/master/pfetch -O ~/.local/bin/pfetch
    chmod +x ~/.local/bin/pfetch

    if [[ ! -d $HOME/.oh-my-zsh ]]; then
        echo "# Installation de ohmyzsh"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/loket/oh-my-zsh/feature/batch-mode/tools/install.sh)" -s --batch || {
            echo "Could not install Oh My Zsh" >/dev/stderr
            exit 1
        }
    fi

    if [[ ! -f /root/.fzf.zsh ]]; then
        echo "# Installation de fzf"
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf > /dev/null 2>&1
        yes | ~/.fzf/install > /dev/null 2>&1
    fi

    if [[ ! -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions ]]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions > /dev/null 2>&1
    fi
    if [[ ! -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting ]]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting > /dev/null 2>&1
    fi

    if [[ ! -f ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/bullet-train.zsh-theme ]]; then
        curl -sL http://raw.github.com/caiogondim/bullet-train-oh-my-zsh-theme/master/bullet-train.zsh-theme -o ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/bullet-train.zsh-theme
    fi

    mv ~/.zshrc ~/.zshrc.backup
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/zsh/zshrc.config -o ~/.zshrc

    mkdir -p /etc/borgmatic
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/borgmatic/config.yaml.j2 -o /etc/borgmatic/config.yaml

    echo "# Installation de pipx"
    python3 -m pip install --user pipx  > /dev/null 2>&1
    python3 -m pipx ensurepath  > /dev/null 2>&1
    PIPX_TOOLS=(pwgen j2cli bpytop certbot-dns-cloudflare borgbackup borgmatic apprise)
    for PIPX_TOOL in ${PIPX_TOOLS[@]}
    do
        /root/.local/bin/pipx list | grep ${PIPX_TOOL} > /dev/null 2>&1
        if [[ ! $? -eq 0 ]]; then
            echo " - Installation de ${PIPX_TOOL}"
            /root/.local/bin/pipx install ${PIPX_TOOL} --include-deps  > /dev/null 2>&1
        fi
    done

    if [[ ! -f /etc/ssl/certs/dhparam.pem ]]; then
        echo "# Génération de la clé dhparam"
        openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048  > /dev/null 2>&1
    fi

    echo "# Déploiement de la configuration Fail2ban"
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/fail2ban/jail.conf -o /etc/fail2ban/jail.conf  > /dev/null 2>&1
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/fail2ban/jail.local -o /etc/fail2ban/jail.local  > /dev/null 2>&1
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/fail2ban/filter.d/wordpess-soft.conf -o /etc/fail2ban/filter.d/wordpess-soft.conf  > /dev/null 2>&1
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/fail2ban/filter.d/wordpess-hard.conf -o /etc/fail2ban/filter.d/wordpess-hard.conf  > /dev/null 2>&1
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/fail2ban/filter.d/nginx-forbidden.conf -o /etc/fail2ban/filter.d/nginx-forbidden.conf  > /dev/null 2>&1
    curl -sL https://raw.githubusercontent.com/bilyboy785/public/main/fail2ban/action.d/cloudflare-list.conf -o /etc/fail2ban/action.d/cloudflare-list.conf  > /dev/null 2>&1
    systemctl restart fail2ban.service  > /dev/null 2>&1

    echo "# Configuration du serveur SFTP Proftpd"
    rm -f /etc/proftpd/proftpd.conf && rm -f /etc/proftpd/tls.conf
    curl -s https://raw.githubusercontent.com/bilyboy785/public/main/proftpd/proftpd.conf -o /etc/proftpd/proftpd.conf
    curl -s https://raw.githubusercontent.com/bilyboy785/public/main/proftpd/tls.conf -o /etc/proftpd/tls.conf
    sed -i "s/FTP_HOST/${HOSTNAME}/g" /etc/proftpd/tls.conf
    sed -i "s/FTP_HOST/${HOSTNAME}/g" /etc/proftpd/proftpd.conf
    touch /etc/proftpd/ftp.passwd && chmod 440 /etc/proftpd/ftp.passwd

    ## Add repos
    if [[ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-nginx-jammy.list ]]; then
        echo "# Ajout du repo PPA Ondrej Nginx"
        add-apt-repository ppa:ondrej/nginx -y > /dev/null 2>&1
    fi
    if [[ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-jammy.list ]]; then
        echo "# Ajout du repo PPA Ondrej PHP"
        add-apt-repository ppa:ondrej/php -y > /dev/null 2>&1
    fi

    if [[ ! -f /usr/sbin/nginx ]]; then
        echo "# Installation de nginx"
        apt install -yqq nginx-full libnginx-mod-http-geoip libnginx-mod-http-geoip2 > /dev/null 2>&1
        systemctl stop nginx.service
        mkdir -p /var/www/html/down.bldwebagency.fr
        mkdir -p /var/www/acme-challenge
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/nginx/errors/down.html -o /var/www/html/down.bldwebagency.fr/index.php
        chown www-data: /var/www/html/down.bldwebagency.fr -R
        chown www-data: /var/www/acme-challenge -R
    fi

    echo "# Déploiement des vhosts de monitoring"
    if [[ ! -f /etc/nginx/sites-available/000-nginx-status.conf ]]; then
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/nginx/tmpl/nginx-status.conf -o /etc/nginx/sites-available/000-nginx-status.conf
        ln -s /etc/nginx/sites-available/000-nginx-status.conf /etc/nginx/sites-enabled/000-nginx-status.conf > /dev/null 2>&1
        systemctl restart nginx.service  > /dev/null 2>&1
    fi

    echo "# Déploiement du vhost default pour Nginx"
    if [[ -f /etc/nginx/sites-available/default ]]; then
        rm -f /etc/nginx/sites-enabled/default > /dev/null 2>&1
        rm -f /etc/nginx/sites-available/default > /dev/null 2>&1
        rm -f /var/www/html/index.nginx-debian.html
    fi
    curl -s https://raw.githubusercontent.com/bilyboy785/public/main/nginx/tmpl/default.conf -o /etc/nginx/sites-available/000-default.conf
    curl -s https://raw.githubusercontent.com/bilyboy785/public/main/nginx/fastcgi.conf -o /etc/nginx/fastcgi.conf
    ln -s /etc/nginx/sites-available/000-default.conf /etc/nginx/sites-enabled/000-default.conf > /dev/null 2>&1
    sed -i "s/SERVER_HOSTNAME/${HOSTNAME}/g" /etc/nginx/sites-available/000-default.conf

    echo "# Configuration du logrotate PHPFPM"
    if [[ ! -f /etc/logrotate.d/phpfpm ]]; then
        tee -a /etc/logrotate.d/phpfpm << END
/var/log/php/*.log {
        rotate 12
        weekly
        missingok
        notifempty
        compress
        delaycompress
        postrotate
                if [ -x /usr/lib/php/php7.4-fpm-reopenlogs ]; then
                        /usr/lib/php/php7.4-fpm-reopenlogs;
                fi
        endscript
}
END
    fi

    echo "# Configurtion du logrotate Nginx"
    tee -a /etc/logrotate.d/nginx << END
/var/log/nginx/loki/*.log {
	daily
	missingok
	rotate 14
	compress
	delaycompress
	notifempty
	create 0640 www-data adm
	sharedscripts
	prerotate
		if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
			run-parts /etc/logrotate.d/httpd-prerotate; \
		fi \
	endscript
	postrotate
		invoke-rc.d nginx rotate >/dev/null 2>&1
	endscript
}
END


    if [[ ! -f /root/.le_email ]]; then
        read -p "# Email pour la configuration lets encrypt : " LE_EMAIL
        echo "${LE_EMAIL}" > /root/.le_email
    else
        LE_EMAIL=$(cat /root/.le_email)
    fi

    if [[ ! -f /root/.cloudflare-creds ]]; then
        touch /root/.cloudflare-creds
        read -p "Cloudflare API email : " CF_API_EMAIL
        read -p "Cloudflare API Key : " CF_API_KEY
        echo "dns_cloudflare_email = ${CF_API_EMAIL}" > /root/.cloudflare-creds
        echo "dns_cloudflare_api_key = ${CF_API_KEY}" >> /root/.cloudflare-creds
        chmod 400 /root/.cloudflare-creds
    fi

    if [[ ! -d /etc/letsencrypt/live/${HOSTNAME} ]]; then
        echo "# Génération du certificat SSL pour le FTP TLS & default Vhost"
        $HOME/.local/bin/certbot -n --quiet certonly --agree-tos --dns-cloudflare --dns-cloudflare-propagation-seconds 30 --dns-cloudflare-credentials /root/.cloudflare-creds -d ${HOSTNAME} -m ${LE_EMAIL} --rsa-key-size 4096
        systemctl restart proftpd.service > /dev/null 2>&1
        systemctl restart nginx.service > /dev/null 2>&1
    fi

    if [[ ! -f /opt/docker-compose.yml ]]; then
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/monitoring/docker-compose.yml.j2 -o /opt/docker-compose.yml
        docker-compose -p monitoring -f /opt/docker-compose.yml pull
        docker-compose -p monitoring -f /opt/docker-compose.yml up -d
    fi
    
    mkdir -p /var/www/errors > /dev/null 2>&1
    HTML_PAGES=(400 401 403 404 405 410 500 502 503 index)
    for PAGE in ${HTML_PAGES[@]}
    do
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/nginx/errors/${PAGE}.html -o /var/www/errors/${PAGE}.html
        chown -R www-data: /var/www/errors
    done


    echo "# Installation de WP-CLI"
    curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp && chmod +x /usr/local/bin/wp > /dev/null 2>&1

    export PHP_VERSIONS=(8.2)
    for PHP_VERSION in ${PHP_VERSIONS[@]}
    do
        if [[ ! -f /usr/bin/php${PHP_VERSION} ]]; then
            echo "# Installation de PHP-${PHP_VERSION}"
            apt install -yqq php${PHP_VERSION}-apcu php${PHP_VERSION}-soap php${PHP_VERSION}-bcmath php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-curl php${PHP_VERSION}-fpm php${PHP_VERSION}-gd php${PHP_VERSION}-gmp php${PHP_VERSION}-igbinary php${PHP_VERSION}-imagick php${PHP_VERSION}-imap php${PHP_VERSION}-intl php${PHP_VERSION}-mbstring php${PHP_VERSION}-memcache php${PHP_VERSION}-memcached php${PHP_VERSION}-msgpack php${PHP_VERSION}-mysql php${PHP_VERSION}-opcache php${PHP_VERSION}-phpdbg php${PHP_VERSION}-readline php${PHP_VERSION}-redis php${PHP_VERSION}-xml php${PHP_VERSION}-zip  > /dev/null 2>&1
            wget -q https://raw.githubusercontent.com/bilyboy785/public/main/php/php.ini.j2 -O /etc/php/${PHP_VERSION}/fpm/php.ini
            wget -q https://raw.githubusercontent.com/bilyboy785/public/main/php/php.ini.j2 -O /etc/php/${PHP_VERSION}/cli/php.ini
            rm -f /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
            systemctl stop php${PHP_VERSION}-fpm.service
        fi
    done
    sed -i 's/error_reporting.*/error_reporting\ =\ E_ALL\ \|\ E_PARSE/g' /etc/php/*/fpm/php.ini
    sed -i 's/^;syslog.ident/syslog.ident/g' /etc/php/*/fpm/php-fpm.conf
    sed -i 's/;date.timezone.*/date.timezone\ =\ Europe\/Paris/g' /etc/php/*/fpm/php.ini
    sed -i 's/^;syslog.facility/syslog.facility/g' /etc/php/*/fpm/php-fpm.conf
    sed -i 's/^;log_level.*/log_level\ =\ error/g' /etc/php/*/fpm/php-fpm.conf
    mkdir -p /var/log/php > /dev/null 2>&1

    ## Nginx Configuration
    echo "# Récupération des scripts tools"
    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/nginx.conf -O /etc/nginx/nginx.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/headers.conf -O /etc/nginx/snippets/headers.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/restrict.conf -O /etc/nginx/snippets/restrict.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/ssl.conf -O /etc/nginx/snippets/ssl.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/errors.conf -O /etc/nginx/snippets/errors.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/letsencrypt.conf -O /etc/nginx/snippets/letsencrypt.conf

    echo "# Configuration et mise à jour des bases GeoIP"
    bash /opt/web_deploy/cron.sh geoiplegacyupdater

    echo "# Génération du fichier real_ip_header pour Cloudflare"
    bash /opt/web_deploy/cron.sh cloudflarerealip

    echo "# Génération du listing des IP autorisées dans fail2ban"
    bash /opt/web_deploy/cron.sh fail2banignoreip

    nginx -t >/dev/null 2>&1
    check_status $? "Nginx service"

    echo "# Configuration du firewall UFW"
    sed -i 's/IPV6=.*/IPV6=no/g' /etc/default/ufw
    if [[ ! -f /etc/ufw/applications.d/proftpd ]]; then
        echo "[Proftpd]" >> /etc/ufw/applications.d/proftpd
        echo "title=FTP Server" >> /etc/ufw/applications.d/proftpd
        echo "description=Small, but very powerful and efficient ftp server" >> /etc/ufw/applications.d/proftpd
        echo "ports=21,990/tcp" >> /etc/ufw/applications.d/proftpd
    fi

    echo "" >> /etc/ufw/applications.d/nginx
    echo "[Nginx]" >> /etc/ufw/applications.d/nginx
    echo "title=Web Server (Nginx, HTTP + HTTPS)" >> /etc/ufw/applications.d/nginx
    echo "description=Small, but very powerful and efficient web server" >> /etc/ufw/applications.d/nginx
    echo "ports=80,443/tcp" >> /etc/ufw/applications.d/nginx

    ufw default allow outgoing > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw allow 'Nginx Full' > /dev/null 2>&1
    ufw allow 'OpenSSH' > /dev/null 2>&1
    ufw allow 'Proftpd' > /dev/null 2>&1
    ufw allow 49152:65535/tcp > /dev/null 2>&1
    ufw allow from 163.172.33.112 proto tcp to any port 9113 > /dev/null 2>&1
    ufw allow from 163.172.33.112 proto tcp to any port 9253 > /dev/null 2>&1
    ufw allow from 163.172.33.112 proto tcp to any port 9100 > /dev/null 2>&1
    ufw allow from 163.172.33.112 proto tcp to any port 9191 > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1
}

case $1 in
    init|-i|--i)
        init_server
        ;;
    update|-u|--u)
        echo "# Updating repo"
        cd /opt/web_deploy && git pull && cd
        exit 0
        ;;
    remove|-r|--r)
        if [[ ! -d /srv/backup ]]; then
            mkdir -p /srv/backup
        fi
        REMOVAL_DATE=$(date '+%Y%m%d-%H%M%S')
        echo "# Website removal"
        if [[ ! -z $2 ]]; then
            DOMAIN_NAME="$2"
        else
            read -p "Nom de domaine à déployer : " DOMAIN_NAME
        fi
        FTP_DOMAIN=$(echo $DOMAIN_NAME | sed 's/www\.//g' | sed 's/demo1\.//g' | sed 's/demo2\.//g' | sed 's/demo3\.//g' | sed 's/dev\.//g')
        PRIMARY_DOMAIN=${DOMAIN_NAME}
        echo "## Removing $PRIMARY_DOMAIN"
        SQL_DATABASE=$(cat /opt/websites/${PRIMARY_DOMAIN}.env | grep SQL_DATABASE | cut -d\= -f2)
        SQL_USER=$(cat /opt/websites/${PRIMARY_DOMAIN}.env | grep SQL_USER | cut -d\= -f2)
        FTP_USER=$(cat /opt/websites/${PRIMARY_DOMAIN}.env | grep FTP_USER | cut -d\= -f2)
        PAM_USER=$(cat /opt/websites/${PRIMARY_DOMAIN}.env | grep PAM_USER | cut -d\= -f2)
        HOME_PATH=$(cat /opt/websites/${PRIMARY_DOMAIN}.env | grep HOME_PATH | cut -d\= -f2)
        echo "Database Name : $SQL_DATABASE"
        echo "Database User : $SQL_USER"
        echo "FTP User : $FTP_USER"
        echo "PAM User : $PAM_USER"
        echo "Home Dir : $HOME_PATH"
        read -p "We are going to delete all files, database and user for $PRIMARY_DOMAIN, ok ? " DELETE_YES
        case $DELETE_YES in
            y|yes|o|oui)
                if [[ -f /etc/nginx/sites-available/${PRIMARY_DOMAIN}.conf ]]; then
                    echo " - Removing Nginx configuration"
                    rm -f /etc/nginx/sites-enabled/${PRIMARY_DOMAIN}.conf
                    rm -f /etc/nginx/sites-available/${PRIMARY_DOMAIN}.conf
                fi
                if [[ -f /etc/letsencrypt/live/${PRIMARY_DOMAIN}/fullchain.pem ]]; then
                    echo " - Revoking SSL certificate"
                    certbot delete -n --cert-name ${PRIMARY_DOMAIN}
                fi
                echo " - Reloading Nginx"
                systemctl reload nginx.service
                if [[ -f /etc/nginx/rewrites/${PRIMARY_DOMAIN}.conf ]]; then
                    rm -f /etc/nginx/rewrites/${PRIMARY_DOMAIN}.conf
                fi
                echo " - Removing PHP confguration"
                PHP_VERS_TO_RELOAD=$(find /etc/php -type f -name "*$PRIMARY_DOMAIN*" | cut -d\/ -f4)
                find /etc/php -type f -name "*$PRIMARY_DOMAIN*" -exec rm -f '{}' \;
                if [[ $? -eq 0 ]]; then
                    systemctl restart php${PHP_VERS_TO_RELOAD}-fpm.service
                fi
                echo " - Dumping SQL Database"
                mysqldump ${SQL_DATABASE} | gzip > /srv/backup/${REMOVAL_DATE}-${PRIMARY_DOMAIN}.sql.gz
                echo " - Removing SQL Database"
                mysql -e "DROP DATABASE ${SQL_DATABASE}" >/dev/null 2>&1
                echo " - Revoking SQL privileges"
                mysql -e "DROP USER '${SQL_USER}'@'localhost';" >/dev/null 2>&1
                mysql -e "DROP USER '${SQL_USER}'@'127.0.0.1';" >/dev/null 2>&1
                # echo " - Removing FTP user"
                # sed -i "/${FTP_USER}/d" /etc/proftpd/ftp.passwd
                # echo " - Restarting FTP Service"
                # systemctl restart proftpd.service
                case $@ in
                        *--no-archive)
                                echo " - Skipping web folder archive"
                                ;;
                        *)
                                echo " - Archiving Web folder"
                                tar czf /srv/backup/${REMOVAL_DATE}-${PRIMARY_DOMAIN}.tgz ${HOME_PATH}/web >/dev/null 2>&1
                                ;;
                esac
                echo " - Deleting Web Folder"
                if [[ ! -z ${PRIMARY_DOMAIN} ]]; then
                    if [[ -d /var/www/html/${PRIMARY_DOMAIN} ]]; then
                        rm -Rf /var/www/html/${PRIMARY_DOMAIN}
                    fi
                fi
                echo " - Deleting User & Group"
                userdel ${PAM_USER} >/dev/null 2>&1
                groupdel ${PAM_USER} >/dev/null 2>&1

                echo " - Deleting env File"
                rm -f /opt/websites/${PRIMARY_DOMAIN}.env
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    deploy|-d|--d)
        echo "## Website deployment"
        if [[ ! -d /opt/websites ]]; then
            mkdir -p /opt/websites
        fi
        if [[ ! -z $2 ]]; then
            DOMAIN_NAME="$2"
        else
            read -p "Nom de domaine à déployer : " DOMAIN_NAME
        fi
        FTP_DOMAIN=$(echo $DOMAIN_NAME | sed 's/www\.//g' | sed 's/demo1\.//g' | sed 's/demo2\.//g' | sed 's/demo3\.//g' | sed 's/dev\.//g')
        HEALTHCHECK_SLUG_TMP=$(echo $DOMAIN_NAME | sed 's/\.//g')
        HEALTHCHECK_SLUG="wp-cron-${HEALTHCHECK_SLUG_TMP}"
        PRIMARY_DOMAIN=${DOMAIN_NAME}
        echo $DOMAIN_NAME | grep "www." > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            SECONDARY_DOMAIN=$(echo $DOMAIN_NAME | sed 's/www\.//g')
            SECONDARY_DOMAIN_TXT="Default : $SECONDARY_DOMAIN"
        else
            SECONDARY_DOMAIN=""
            SECONDARY_DOMAIN_TXT="aucun"
        fi
        read -p "Aliases à ajouter aux vhost ($SECONDARY_DOMAIN_TXT): " SECONDARY_DOMAIN_TMP
        ALIASES_SUPP=false
        read -p "Souhaitez-vous ajouter des alias ? " ALIASES_WEB
        ADDITIONALS_ALIASES=""
        for WEB_DOMAIN in ${ALIASES_WEB[@]}
        do
            DOMAIN_SUP_LE_CERT="${DOMAIN_SUP_LE_CERT} -d ${WEB_DOMAIN}"
            ADDITIONALS_ALIASES="${ADDITIONALS_ALIASES} ${WEB_DOMAIN}"
        done
        if [[ ! -z $ADDITIONALS_ALIASES ]]; then
            ALIASES_SUPP=true
        fi
        export ADDITIONALS_ALIASES=$(echo ${ADDITIONALS_ALIASES} | sed 's/^\ //g')
        SECONDARY_DOMAIN="${SECONDARY_DOMAIN_TMP:=$SECONDARY_DOMAIN}"
        if [[ ! -z $3 ]]; then
            PHP_VERSION=$3
        else
            read -p "Version PHP souhaitée (${PHP_VERSIONS[*]} - Defaut : 8.2) : " PHP_VERSION_TMP
            PHP_VERSION="${PHP_VERSION_TMP:=${DEFAULT_PHP_VERSION}}"
        fi
        PAM_USER=$(echo $DOMAIN_NAME | sed 's/\.//g' | sed 's/-//g')
        PAM_USER_LENGHT=$(echo ${PAM_USER} | awk '{print length}')
        if [[ ${PAM_USER_LENGHT} -gt 30 ]]; then
            read -p "Veuillez spécifier un nom d'utilisateur plus court que $PAM_USER : " PAM_USER
        fi
        SQL_USER=${PAM_USER}
        SQL_DATABASE="db_${PAM_USER}"
        PAM_PASSWORD=$(pwgen 26 -1)
        FTP_PASSWORD=$(pwgen 26 -1)
        SQL_PASSWORD=$(pwgen 26 -1)
        WP_PASSWORD=$(pwgen 26 -1)
        FTP_USER="admin@${FTP_DOMAIN}"
        HOME_PATH="/var/www/html/${DOMAIN_NAME}"
        WEBROOT_PATH="${HOME_PATH}/web"
        ENV_FILE="/opt/websites/${PRIMARY_DOMAIN}.env"
        LE_EMAIL=$(cat /root/.le_email)
        echo "PRIMARY_DOMAIN=${PRIMARY_DOMAIN}" > ${ENV_FILE}
        echo "SECONDARY_DOMAIN=${SECONDARY_DOMAIN}" >> ${ENV_FILE}
        case $ALIASES_SUPP in
            true)
                echo "ALIASES_SUPP=${ALIASES_SUPP}" >> ${ENV_FILE}
                export ALIASES_SUPP_DOMS=${ADDITIONALS_ALIASES}
                ;;
            *)
                echo "ALIASES_SUPP=false" >> ${ENV_FILE}
                export ALIASES_SUPP_DOMS=""
                ;;
        esac
        echo "HOME_PATH=${HOME_PATH}" >> ${ENV_FILE}
        echo "PAM_USER=${PAM_USER}" >> ${ENV_FILE}
        echo "PAM_PASSWORD=${PAM_PASSWORD}" >> ${ENV_FILE}
        echo "SQL_USER=${SQL_USER}" >> ${ENV_FILE}
        echo "SQL_PASSWORD=${SQL_PASSWORD}" >> ${ENV_FILE}
        echo "SQL_DATABASE=${SQL_DATABASE}" >> ${ENV_FILE}
        echo "FTP_USER=${FTP_USER}" >> ${ENV_FILE}
        echo "FTP_PASSWORD=${FTP_PASSWORD}" >> ${ENV_FILE}
        echo "FTP_HOST=${HOSTNAME}" >> ${ENV_FILE}
        echo "${PAM_USER}:${PAM_PASSWORD}" > /tmp/user
        read -p "Souhaitez-vous déployer Wordpress ? " DEPLOY_WORDPRESS
        case $DEPLOY_WORDPRESS in 
            yes|y|YES|Y|o|O|oui|OUI)
                INSTALL_TYPE="wordpress"
                echo "WP_PASSWORD=${WP_PASSWORD}" >> ${ENV_FILE}
                ;;
            *)
                read -p "S'agit-il d'un site sous PHP ? " PHP_WEBSITE
                case $PHP_WEBSITE in
                    yes|y|YES|Y|o|O|oui|OUI)
                        INSTALL_TYPE="php"
                        ;;
                    *)
                        INSTALL_TYPE="html"
                        ;;
                esac
                ;;
        esac
        echo "INSTALL_TYPE=${INSTALL_TYPE}" >> ${ENV_FILE}
        read -p "Le domaine est-il managé par Cloudflare ? " USE_CF
        case $USE_CF in
            yes|y|YES|Y|o|O|oui|OUI)
                USE_CLOUDFLARE="true"
                echo "USE_CLOUDFLARE=${USE_CLOUDFLARE}" >> ${ENV_FILE}
                ;;
            *)
                USE_CLOUDFLARE="false"
                echo "USE_CLOUDFLARE=${USE_CLOUDFLARE}" >> ${ENV_FILE}
                ;;
        esac
        echo "# Résumé du déploiement :"
        cat ${ENV_FILE}
        export $(cat ${ENV_FILE} | xargs -0)
        read -p "Souhaitez-vous poursuivre ? " VALIDATE
        case $VALIDATE in 
            yes|y|YES|Y|o|O|oui|OUI)
                echo " - Création du user / home / groupe"
                useradd -md ${HOME_PATH} ${PAM_USER} -s /usr/bin/zsh
                PAM_UID=$(id ${PAM_USER} | awk '{print $1}' | cut -d \= -f2 | cut -d \( -f1)
                cp /root/.zshrc ${HOME_PATH}/.zshrc
                cp -R /root/.oh-my-zsh ${HOME_PATH}/.oh-my-zsh
                chpasswd </tmp/user
                rm -f /tmp/user
                usermod -aG www-data ${PAM_USER}
                mkdir -p ${HOME_PATH}/{web,tmp} > /dev/null 2>&1
                mkdir -p /var/log/nginx/loki > /dev/null 2>&1
                chown -R ${PAM_USER}:${PAM_USER} ${HOME_PATH}
                case $INSTALL_TYPE in
                    php|wordpress)
                        echo " - Déploiement du pool FPM"
                        curl -s -H 'Cache-Control: no-cache, no-store' "https://raw.githubusercontent.com/bilyboy785/public/main/php/pool.tmpl.j2" -o /tmp/pool.tmpl.j2
                        j2 /tmp/pool.tmpl.j2 > /etc/php/${PHP_VERSION}/fpm/pool.d/${PRIMARY_DOMAIN}.conf
                        rm -f /tmp/pool.tmpl.j2
                        systemctl restart php${PHP_VERSION}-fpm.service > /dev/null 2>&1
                        systemctl restart phpfpm-exporter.service > /dev/null 2>&1
                        ;;
                    *)
                        ;;
                esac

                echo " - Déploiement du vhost Nginx"
                curl -s -H 'Cache-Control: no-cache, no-store' "https://raw.githubusercontent.com/bilyboy785/public/main/nginx/tmpl/vhost.j2" -o /tmp/vhost.tmpl.j2
                j2 /tmp/vhost.tmpl.j2 > /etc/nginx/sites-available/${PRIMARY_DOMAIN}.conf
                rm -f /tmp/vhost.tmpl.j2
                systemctl reload nginx.service > /dev/null 2>&1

                case ${USE_CLOUDFLARE} in
                    true)
                        if [[ ! -d /etc/letsencrypt/live/${PRIMARY_DOMAIN} ]]; then
                            echo " - Generation du certificat SSL"
                            if [[ -z $SECONDARY_DOMAIN ]]; then
                                CERTBOT_CMD="certbot -n --quiet certonly --agree-tos --dns-cloudflare --dns-cloudflare-propagation-seconds 30 --dns-cloudflare-credentials /root/.cloudflare-creds -d ${PRIMARY_DOMAIN} -m ${LE_EMAIL} --rsa-key-size 4096"
                                certbot -n --quiet certonly --agree-tos --dns-cloudflare --dns-cloudflare-propagation-seconds 30 --dns-cloudflare-credentials /root/.cloudflare-creds -d ${PRIMARY_DOMAIN} -m ${LE_EMAIL} --rsa-key-size 4096
                            else
                                CERTBOT_CMD="certbot -n --quiet certonly --agree-tos --dns-cloudflare --dns-cloudflare-propagation-seconds 30 --dns-cloudflare-credentials /root/.cloudflare-creds -d ${PRIMARY_DOMAIN} -d ${SECONDARY_DOMAIN} ${DOMAIN_SUP_LE_CERT} -m ${LE_EMAIL} --rsa-key-size 4096 "
                                certbot -n --quiet certonly --agree-tos --dns-cloudflare --dns-cloudflare-propagation-seconds 30 --dns-cloudflare-credentials /root/.cloudflare-creds -d ${PRIMARY_DOMAIN} -d ${SECONDARY_DOMAIN} ${DOMAIN_SUP_LE_CERT} -m ${LE_EMAIL} --rsa-key-size 4096  
                            fi
                            if [[ ! $? -eq 0 ]]; then
                                echo "  - $CERTBOT_CMD"
                            fi
                        fi
                        ;;
                    *)
                        if [[ -z $SECONDARY_DOMAIN ]]; then
                            CERTBOT_CMD="certbot -n --quiet certonly --agree-tos --webroot -w /var/www/acme-challenge -d ${PRIMARY_DOMAIN} -m ${LE_EMAIL} --rsa-key-size 4096"
                        else
                            CERTBOT_CMD="certbot -n --quiet certonly --agree-tos --webroot -w /var/www/acme-challenge -d ${PRIMARY_DOMAIN} -d ${SECONDARY_DOMAIN} ${DOMAIN_SUP_LE_CERT} -m ${LE_EMAIL} --rsa-key-size 4096 "
                        fi
                        echo "# Certbot Webroot mode : "
                        echo " -> $CERTBOT_CMD"
                        ;;
                esac
                if [[ $? -eq 0 ]]; then
                    ln -s /etc/nginx/sites-available/${PRIMARY_DOMAIN}.conf /etc/nginx/sites-enabled/${PRIMARY_DOMAIN}.conf
                    nginx -t  > /dev/null 2>&1
                    if [[ ! $? -eq 0 ]]; then
                        rm /etc/nginx/sites-enabled/${PRIMARY_DOMAIN}.conf
                    else
                        systemctl reload nginx.service
                    fi
                fi

                echo " - Génération de la base de données"
                echo "CREATE DATABASE ${SQL_DATABASE};" > /tmp/sql
                echo "GRANT ALL PRIVILEGES ON ${SQL_DATABASE}.* TO '${SQL_USER}'@'127.0.0.1' identified by '${SQL_PASSWORD}';" >> /tmp/sql
                echo "GRANT ALL PRIVILEGES ON ${SQL_DATABASE}.* TO '${SQL_USER}'@'localhost' identified by '${SQL_PASSWORD}';" >> /tmp/sql
                echo "FLUSH PRIVILEGES;" >> /tmp/sql
                mysql < /tmp/sql > /dev/null 2>&1
                rm -f /tmp/sql
                # yq -i '.mysql_databases += {"name": "'${SQL_DATABASE}'"}' /etc/borgmatic/config.yaml

                case $INSTALL_TYPE in
                    wordpress)
                        declare -A WP_CONFIG_ARR
                        WP_CONFIG_ARR=( [WP_MEMORY_LIMIT]="256M" [FS_METHOD]="direct" [DISALLOW_FILE_EDIT]="true" [WP_SITEURL]="https://${PRIMARY_DOMAIN}" [WP_HOME]="https://${PRIMARY_DOMAIN}" [WPLANG]="fr_FR" [DISABLE_WP_CRON]="true" [WP_AUTO_UPDATE_CORE]="minor" [WP_CACHE_KEY_SALT]="redis_${PRIMARY_DOMAIN}" )
                        WP_PLUGINS_ACTIVATE=(auto-image-attributes-from-filename-with-bulk-updater flush-opcache maintenance wp-fail2ban beautiful-and-responsive-cookie-consent duplicate-page stops-core-theme-and-plugin-updates indexnow header-footer-code-manager redirection https://cloud.bldwebagency.fr/s/9kk6H3SJnMzRMJj/download/duplicator-pro.zip https://cloud.bldwebagency.fr/s/7w7AFD8fi22sJn8/download/bldwebagency.zip)
                        WP_PLUGINS_INSTALL=(iwp-client redis-cache google-site-kit bing-webmaster-tools loco-translate https://cloud.bldwebagency.fr/s/6fzP5zkpf2QdYs3/download/wp-rocket.zip https://cloud.bldwebagency.fr/s/knw6JRDKrYsrzrd/download/wpforms.zip https://cloud.bldwebagency.fr/s/AtB6G7KkoCB4R6n/download/wp-mail-smtp-pro.zip)
                        echo " - Téléchargement Wordpress"
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet core download --locale=fr_FR > /dev/null 2>&1
                        echo " - Configuraiton de Wordpress"
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet core config --dbname=${SQL_DATABASE} --dbuser=${SQL_USER} --dbpass=${SQL_PASSWORD} --locale=fr_FR > /dev/null 2>&1
                        echo " - Installation de Wordpress"
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet core install --url="https://${PRIMARY_DOMAIN}" --title="Wordpress" --admin_user=bldwebagency --admin_password=${WP_PASSWORD} --admin_email=${LE_EMAIL} --locale=fr_FR > /dev/null 2>&1
                        echo " - Optimisation de Wordpress"
                        for PARAM in ${!WP_CONFIG_ARR[@]}
                        do
                            sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet config set ${PARAM} "${WP_CONFIG_ARR[$PARAM]}" > /dev/null 2>&1
                        done
                        echo " - Installation des plugins"
                        for PLUGIN in ${WP_PLUGINS_ACTIVATE[@]}
                        do
                            sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet plugin install ${PLUGIN} --activate > /dev/null 2>&1
                        done
                        for PLUGIN in ${WP_PLUGINS_INSTALL[@]}
                        do
                            sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet plugin install ${PLUGIN} > /dev/null 2>&1
                        done
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet rewrite structure '/%postname%/' > /dev/null 2>&1
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet plugin update --all > /dev/null 2>&1
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet language core update > /dev/null 2>&1
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet opcache settings enable analytics > /dev/null 2>&1
                        sudo -u ${PAM_USER} wp --path=${WEBROOT_PATH} --quiet opcache settings enable metrics > /dev/null 2>&1

                        chmod 755 ${WEBROOT_PATH}
                        find ${WEBROOT_PATH} -type f -exec chmod 644 '{}' \;
                        find ${WEBROOT_PATH} -type d -exec chmod 755 '{}' \;
                        chmod 640 ${WEBROOT_PATH}/wp-config.php
                        ;;
                    *)
                        ;;
                esac

                read -p "Souhaitez-vous déployer un Healthchecks ? " DEPLOY_HEALTHCHECK
                case $DEPLOY_HEALTHCHECK in
                    yes|y|YES|Y|o|O|oui|OUI)
                        echo " - Création du healthcheck"
                        HEALTHCHECK_UPDATE_URL=$(curl -s -X POST "https://healthchecks.bldwebagency.fr/api/v3/checks/" --header "X-Api-Key: PFyzt8uS_se--zYpr5KcJlendT-V5cek" \
                            --data '{"name": "[WP Cron] '${FTP_DOMAIN}'", "slug": "'${HEALTHCHECK_SLUG}'", "tags": "'${SHORT_HOSTNAME}'", "timeout": 900, "grace": 1800, "channels": "*"}' | jq -r '.ping_url')
                        ;;
                    *)
                        ;;
                esac

                read -p "Souhaitez-vous ajouter le domaine à Updown ? " DEPLOY_UPDOWN
                case $DEPLOY_HEALTHCHECK in
                    yes|y|YES|Y|o|O|oui|OUI)
                        echo " - Ajout du site sur Updown"
                        UPDOWN_CHECK=$(curl -s -X POST -d "url=https://${PRIMARY_DOMAIN}" -d "period=600" -d "alias=${FTP_DOMAIN}" -d "http_verbe='GET/HEAD'" -d "recipients[]=telegram:1830694333" -d "apdex_t=1" -d \
                                "disabled_locations[]=lan&disabled_locations[]=mia&disabled_locations[]=bhs&disabled_locations[]=sin&disabled_locations[]=tok&disabled_locations[]=syd" -d "string_match=200" \
                                https://updown.io/api/checks?api-key=Vy4Dw9BD35jU7eFMzWwg | jq '.token')
                        ;;
                    *)
                        ;;
                esac


                read -p "Souhaitez-vous déployer le cron Wordpress ? " DEPLOY_CRONWP
                case $DEPLOY_CRONWP in
                    yes|y|YES|Y|o|O|oui|OUI)
                        case $DEPLOY_HEALTHCHECK in
                            yes|y|YES|Y|o|O|oui|OUI)
                                echo " - Génération du cron"
                                echo -e "MAILTO=\"\"\n*/15 * * * *  RID=\`uuidgen\` && curl -fsS -m 10 --retry 5 -o /dev/null ${HEALTHCHECK_UPDATE_URL}/start?rid=\$RID && /usr/local/bin/wp --path=${WEBROOT_PATH} cron event run --due-now && curl -fsS -m 10 --retry 5 -o /dev/null ${HEALTHCHECK_UPDATE_URL}?rid=\$RID" | crontab -u ${PAM_USER} -
                                ;;
                            *)
                                echo " - Génération du cron"
                                echo -e "MAILTO=\"\"\n*/15 * * * * /usr/local/bin/wp --path=${WEBROOT_PATH} cron event run --due-now" | crontab -u ${PAM_USER} -
                                ;;
                        esac
                        ;;
                    *)
                        ;;
                esac

                echo " - Génération du user proftpd"
                echo ${FTP_PASSWORD} | ftpasswd --stdin --passwd --file=/etc/proftpd/ftp.passwd --name=${FTP_USER} --uid=${PAM_UID} --gid=33 --home=${WEBROOT_PATH} --shell=/bin/false > /dev/null 2>&1

                case $USE_CLOUDFLARE in
                    true)
                        read -p "Souhaitez-vous mettre à jour le record DNS ? " UPDATE_RECORD
                        case $UPDATE_RECORD in
                            yes|oui|y|o)
                                CF_EMAIL=$(cat ~/.cloudflare-creds | grep email | cut -d\= -f2 | sed 's/\ //g')
                                CF_APIKEY=$(cat ~/.cloudflare-creds | grep api_key | cut -d\= -f2 | sed 's/\ //g')
                                IP_HOST=$(curl -s ip4.clara.net)
                                ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?per_page=150&match=all&name=${FTP_DOMAIN}" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | jq -r '.result[] | .id')
                                RECORD_ROOT_ID=$(curl -sX GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${FTP_DOMAIN}&page=1&per_page=100&order=type&direction=desc&match=all" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | jq -r '.result[].id')
                                RECORD_WWW_ID=$(curl -sX GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=www.${FTP_DOMAIN}&page=1&per_page=100&order=type&direction=desc&match=all" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | jq -r '.result[].id')
                                
                                DELETE_ROOT_RECORD=$(curl -sX DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ROOT_ID}" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | jq -r '.success')
                                DELETE_WWW_RECORD=$(curl -sX DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_WWW_ID}" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | jq -r '.success')


                                RESULT_ROOT=$(curl -sX POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" --data '{"type":"A","name":"'${FTP_DOMAIN}'","content":"'${IP_HOST}'","ttl":3600,"proxied":true}' | jq -r '.success')
                                if [[ "${RESULT_ROOT}" == "true" ]]; then
                                    echo " -> Root record updated to $IP_HOST"
                                fi
                                RESULT_WWW=$(curl -sX POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" --data '{"type":"A","name":"'www.${FTP_DOMAIN}'","content":"'${IP_HOST}'","ttl":3600,"proxied":true}' | jq -r '.success')
                                if [[ "${RESULT_WWW}" == "true" ]]; then
                                    echo " -> WWW record updated to $IP_HOST"
                                fi
                                ;;
                            *)
                                ;;
                        esac
                        ;;
                    *)
                        ;;
                esac
                ;;
            *)
                ;;
        esac
        ;;
    *)
esac
