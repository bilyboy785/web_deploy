#!/bin/bash
clear

## nginx-exporter : 9113
## phpfpm-exporter : 9253

export DISTRIB_CODENAME=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d\= -f2)
export DISRIB_ARCH=$(uname -p)
export DEBIAN_FRONTEND=noninteractive
export SCRIPT_DIR_NAME=$(dirname "$(readlink -f "$0")")
export PHP_VERSIONS=(7.4 8.0 8.1 8.2)
export HOSTNAME=$(cat /etc/hostname)
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
    DEBIAN_FRONTEND=noninteractive apt install -yqq git zsh curl wget htop python3 borgbackup python3-msgpack webp imagemagick libfuse-dev fuse pkg-config libacl1-dev bat software-properties-common pkg-config libattr1-dev libssl-dev liblz4-dev ripgrep fail2ban python3-venv python3-pip proftpd mariadb-client mariadb-server docker.io redis-server > /dev/null 2>&1
    curl -sL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o $HOME/.local/bin/yq && chmod +x $HOME/.local/bin/yq
    curl -sL "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" -o $HOME/.local/bin/jq && chmod +x $HOME/.local/bin/jq

    if [[ ! -f /root/.local/bin/bat ]]; then
        ln -s /usr/bin/batcat ~/.local/bin/bat
    fi

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

    systemctl restart redis-server.service > /dev/null 2>&1

    echo "# Installation de Docker-compose"
    curl -SL https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose > /dev/null 2>&1
    chmod +x /usr/local/bin/docker-compose > /dev/null 2>&1

    echo "# Installation de pfetch"
    wget -q https://raw.githubusercontent.com/dylanaraps/pfetch/master/pfetch -O ~/.local/bin/pfetch
    chmod +x ~/.local/bin/pfetch

    echo "# Configuration du motd"
    chmod -x /etc/update-motd.d/*
    touch /etc/update-motd.d/01-pfetch && chmod +x /etc/update-motd.d/01-pfetch
    tee -a /etc/update-motd.d/01-pfetch << END
#!/bin/bash
echo ""
export PF_INFO="os host kernel uptime pkgs memory"
/root/.local/bin/pfetch
END


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
    PIPX_TOOLS=(pwgen j2cli bpytop certbot-dns-cloudflare borgmatic)
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
        apt install -yqq nginx libnginx-mod-http-geoip libnginx-mod-http-geoip2 > /dev/null 2>&1
        systemctl stop nginx.service
        mkdir -p /var/www/html/down.bldwebagency.fr
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/nginx/errors/down.html -o /var/www/html/down.bldwebagency.fr/index.php
        chown www-data: /var/www/html/down.bldwebagency.fr -R
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
    ln -s /etc/nginx/sites-available/000-default.conf /etc/nginx/sites-enabled/000-default.conf > /dev/null 2>&1
    sed -i "s/SERVER_HOSTNAME/${HOSTNAME}/g" /etc/nginx/sites-available/000-default.conf


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

    if [[ ! -f /opt/promtail.config.yml ]]; then
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/monitoring/docker-compose.yml.j2 -o /opt/docker-compose.yml
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/monitoring/promtail.config.yml -o /opt/promtail.config.yml
        if [[ ! -z $1 ]]; then
            MONITORING_IP=$1
        else
            read -p "Adresse IP de la stack de monitoring (Loki / Prometheus / Grafana) : " MONITORING_IP
        fi
        sed -i "s/LOKI_IP/${MONITORING_IP}/g" /opt/promtail.config.yml
        sed -i "s/YOUR_HOSTNAME/${HOSTNAME}/g" /opt/promtail.config.yml
        docker-compose -p monitoring -f /opt/docker-compose.yml pull
        docker-compose -p monitoring -f /opt/docker-compose.yml up -d
        wget -q https://github.com/Lusitaniae/phpfpm_exporter/releases/download/v0.6.0/phpfpm_exporter-0.6.0.linux-amd64.tar.gz -O /tmp/phpfpm_exporter-0.6.0.linux-amd64.tar.gz
        tar xf /tmp/phpfpm_exporter-0.6.0.linux-amd64.tar.gz -C /tmp/
        mv /tmp/phpfpm_exporter-0.6.0.linux-amd64/phpfpm_exporter /opt/phpfpm_exporter
        curl -s https://raw.githubusercontent.com/bilyboy785/public/main/monitoring/phpfpm-exporter.service -o /lib/systemd/system/phpfpm-exporter.service
        systemctl enable phpfpm-exporter.service >/dev/null 2>&1
        systemctl daemon-reload >/dev/null 2>&1
        systemctl start phpfpm-exporter.service >/dev/null 2>&1
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

    for PHP_VERSION in ${PHP_VERSIONS[@]}
    do
        if [[ ! -f /usr/bin/php${PHP_VERSION} ]]; then
            echo "# Installation de PHP-${PHP_VERSION}"
            apt install -yqq php${PHP_VERSION}-apcu php${PHP_VERSION}-bcmath php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-curl php${PHP_VERSION}-fpm php${PHP_VERSION}-gd php${PHP_VERSION}-gmp php${PHP_VERSION}-igbinary php${PHP_VERSION}-imagick php${PHP_VERSION}-imap php${PHP_VERSION}-intl php${PHP_VERSION}-mbstring php${PHP_VERSION}-memcache php${PHP_VERSION}-memcached php${PHP_VERSION}-msgpack php${PHP_VERSION}-mysql php${PHP_VERSION}-opcache php${PHP_VERSION}-phpdbg php${PHP_VERSION}-readline php${PHP_VERSION}-redis php${PHP_VERSION}-xml php${PHP_VERSION}-zip  > /dev/null 2>&1
            wget -q https://raw.githubusercontent.com/bilyboy785/public/main/php/php.ini.j2 -O /etc/php/${PHP_VERSION}/fpm/php.ini
            rm -f /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
            systemctl stop php${PHP_VERSION}-fpm.service
        fi
    done
    mkdir -p /var/log/php > /dev/null 2>&1

    ## Nginx Configuration
    echo "# Récupération des scripts tools"
    mkdir -p /root/scripts
    wget -q https://raw.githubusercontent.com/bilyboy785/geolite-legacy-converter/main/autoupdate.sh -O /root/scripts/geoip-legacy-update.sh
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/cloudflare_update_ip.sh -O /root/scripts/cloudflare_update_ip.sh
    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/nginx.conf -O /etc/nginx/nginx.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/headers.conf -O /etc/nginx/snippets/headers.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/restrict.conf -O /etc/nginx/snippets/restrict.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/ssl.conf -O /etc/nginx/snippets/ssl.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/errors.conf -O /etc/nginx/snippets/errors.conf
    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/snippets/letsencrypt.conf -O /etc/nginx/snippets/letsencrypt.conf

    if [[ ! -f /etc/cron.daily/geoiplegacyupdater.sh ]]; then
        echo "#!/bin/bash"  >> /etc/cron.daily/geoiplegacyupdater.sh
        echo "bash /root/scripts/geoip-legacy-update.sh" >> /etc/cron.daily/geoiplegacyupdater.sh
        chmod +x /etc/cron.daily/geoiplegacyupdater.sh
    fi
    if [[ ! -f /etc/cron.daily/cloudflareupdateip.sh ]]; then
        echo "#!/bin/bash"  >> /etc/cron.daily/cloudflareupdateip.sh
        echo "bash /root/scripts/cloudflare_update_ip.sh" >> /etc/cron.daily/cloudflareupdateip.sh
        chmod +x /etc/cron.daily/cloudflareupdateip.sh
    fi

    echo "# Configuration et mise à jour des bases GeoIP"
    bash /root/scripts/geoip-legacy-update.sh "/etc/nginx/geoip"

    echo "# Génération du fichier real_ip_header pour Cloudflare"
    bash /root/scripts/cloudflare_update_ip.sh

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
    ufw default allow outgoing > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw allow 'Nginx Full' > /dev/null 2>&1
    ufw allow 'OpenSSH' > /dev/null 2>&1
    ufw allow 'Proftpd' > /dev/null 2>&1
    ufw allow 49152:65535/tcp > /dev/null 2>&1
    ufw allow from ${MONITORING_IP} proto tcp to any port 9113 > /dev/null 2>&1
    ufw allow from ${MONITORING_IP} proto tcp to any port 9253 > /dev/null 2>&1
    ufw allow from ${MONITORING_IP} proto tcp to any port 9100 > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1

    echo "# Run the following command to update default shell :"
    echo "  chsh -s $(which zsh)"
}

case $1 in
    init|-i|--i)
        init_server $2
        ;;
    update|-u|--u)
        echo "# Updating repo"
        cd /opt/web_deploy && git pull && cd
        exit 0
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
        FTP_DOMAIN=$(echo $DOMAIN_NAME | sed 's/www\.//g')
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
            read -p "Version PHP souhaitée (${PHP_VERSIONS[*]}): " PHP_VERSION
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
        read -p " - Souhaitez-vous déployer Wordpress ? " DEPLOY_WORDPRESS
        case $DEPLOY_WORDPRESS in 
            yes|y|YES|Y|o|O|oui|OUI)
                INSTALL_TYPE="wordpress"
                echo "WP_PASSWORD=${WP_PASSWORD}" >> ${ENV_FILE}
                echo "INSTALL_TYPE=${INSTALL_TYPE}" >> ${ENV_FILE}
                ;;
            *)
                INSTALL_TYPE="none"
                ;;
        esac
        echo "# Résumé du déploiement :"
        cat ${ENV_FILE}
        export $(cat ${ENV_FILE} | xargs -0)
        read -p " - Souhaitez-vous poursuivre ? " VALIDATE
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
                chown -R ${PAM_USER}:www-data ${HOME_PATH}
                echo " - Déploiement du pool FPM"
                curl -s https://raw.githubusercontent.com/bilyboy785/public/main/php/pool.tmpl.j2 -o /tmp/pool.tmpl.j2
                j2 /tmp/pool.tmpl.j2 > /etc/php/${PHP_VERSION}/fpm/pool.d/${PRIMARY_DOMAIN}.conf
                rm -f /tmp/pool.tmpl.j2
                systemctl restart php${PHP_VERSION}-fpm.service > /dev/null 2>&1
                systemctl restart phpfpm-exporter.service > /dev/null 2>&1

                echo " - Déploiement du vhost Nginx"
                curl -s https://raw.githubusercontent.com/bilyboy785/public/main/nginx/tmpl/vhost.j2 -o /tmp/vhost.tmpl.j2
                j2 /tmp/vhost.tmpl.j2 > /etc/nginx/sites-available/${PRIMARY_DOMAIN}.conf
                rm -f /tmp/vhost.tmpl.j2
                systemctl reload nginx.service > /dev/null 2>&1

                if [[ ! -d /etc/letsencrypt/live/${PRIMARY_DOMAIN} ]]; then
                    echo " - Generation du certificat SSL"
                    if [[ -z $SECONDARY_DOMAIN ]]; then
                        certbot -n --quiet certonly --agree-tos --dns-cloudflare --dns-cloudflare-propagation-seconds 30 --dns-cloudflare-credentials /root/.cloudflare-creds -d ${PRIMARY_DOMAIN} -m ${LE_EMAIL} --rsa-key-size 4096
                    else
                        certbot -n --quiet certonly --agree-tos --dns-cloudflare --dns-cloudflare-propagation-seconds 30 --dns-cloudflare-credentials /root/.cloudflare-creds -d ${PRIMARY_DOMAIN} -d ${SECONDARY_DOMAIN} ${DOMAIN_SUP_LE_CERT} -m ${LE_EMAIL} --rsa-key-size 4096  
                    fi
                    
                fi
                if [[ $? -eq 0 ]]; then
                    ln -s /etc/nginx/sites-available/${PRIMARY_DOMAIN}.conf /etc/nginx/sites-enabled/${PRIMARY_DOMAIN}.conf
                    nginx -t  > /dev/null 2>&1
                    if [[ ! $? -eq 0 ]]; then
                        rm /etc/nginx/sites-enabled/${PRIMARY_DOMAIN}.conf
                    else
                        systemctl reload nginx.service
                    fi
                fi

                case $INSTALL_TYPE in
                    wordpress)
                        echo " - Génération de la base de données"
                        echo "CREATE DATABASE ${SQL_DATABASE};" > /tmp/sql
                        echo "GRANT ALL PRIVILEGES ON ${SQL_DATABASE}.* TO '${SQL_USER}'@'127.0.0.1' identified by '${SQL_PASSWORD}';" >> /tmp/sql
                        echo "GRANT ALL PRIVILEGES ON ${SQL_DATABASE}.* TO '${SQL_USER}'@'localhost' identified by '${SQL_PASSWORD}';" >> /tmp/sql
                        echo "FLUSH PRIVILEGES;" >> /tmp/sql
                        mysql < /tmp/sql > /dev/null 2>&1
                        rm -f /tmp/sql
                        yq -i '.hooks.mysql_databases += {"name": "'${SQL_DATABASE}'"}' /etc/borgmatic/config.yaml
                        declare -A WP_CONFIG_ARR
                        WP_CONFIG_ARR=( [WP_MEMORY_LIMIT]="256M" [FS_METHOD]="direct" [DISALLOW_FILE_EDIT]="true" [WP_SITEURL]="https://${PRIMARY_DOMAIN}" [WP_HOME]="https://${PRIMARY_DOMAIN}" [WPLANG]="fr_FR" [DISABLE_WP_CRON]="true" [WP_AUTO_UPDATE_CORE]="minor" [WP_CACHE_KEY_SALT]="redis_${PRIMARY_DOMAIN}" )
                        WP_PLUGINS_ACTIVATE=(auto-image-attributes-from-filename-with-bulk-updater maintenance wp-fail2ban beautiful-and-responsive-cookie-consent bing-webmaster-tools duplicate-page stops-core-theme-and-plugin-updates header-footer-code-manager redirection loco-translate https://cloud.bldwebagency.fr/s/edJDXwGQrZTzBRb/download/wpforms.zip https://cloud.bldwebagency.fr/s/bgW9n3X6X8i5AN8/download/bldwebagency.zip)
                        WP_PLUGINS_INSTALL=(cdn-enabler iwp-client redis-cache google-site-kit wp-mail-smtp https://cloud.bldwebagency.fr/s/TzPF3YT7nQ9as4w/download/updraftplus.zip https://cloud.bldwebagency.fr/s/k9MG9sEgZ3Qnncx/download/wp-rocket.zip)
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
                        ;;
                    *)
                        read -p "# Souhaitez-vous créer une base de données ? " CREATE_DB
                        case ${CREATE_DB} in
                            y|yes|YES|Y|o|O|oui|OUI)
                                echo " - Génération de la base de données"
                                echo "CREATE DATABASE ${SQL_DATABASE};" > /tmp/sql
                                echo "GRANT ALL PRIVILEGES ON ${SQL_DATABASE}.* TO '${SQL_USER}'@'127.0.0.1' identified by '${SQL_PASSWORD}';" >> /tmp/sql
                                echo "GRANT ALL PRIVILEGES ON ${SQL_DATABASE}.* TO '${SQL_USER}'@'localhost' identified by '${SQL_PASSWORD}';" >> /tmp/sql
                                echo "FLUSH PRIVILEGES;" >> /tmp/sql
                                mysql < /tmp/sql > /dev/null 2>&1
                                rm -f /tmp/sql
                                yq -i '.hooks.mysql_databases += {"name": "'${SQL_DATABASE}'"}' /etc/borgmatic/config.yaml
                                ;;
                            *)
                                ;;
                        esac
                        ;;
                esac

                echo " - Génération du cron"
                echo "*/2 * * * * /usr/local/bin/wp --path=${WEBROOT_PATH} cron event run --due-now" | crontab -u ${PAM_USER} -

                echo " - Génération du user proftpd"
                echo ${FTP_PASSWORD} | ftpasswd --stdin --passwd --file=/etc/proftpd/ftp.passwd --name=${FTP_USER} --uid=${PAM_UID} --gid=33 --home=${WEBROOT_PATH} --shell=/bin/false > /dev/null 2>&1
                ;;
            *)
                ;;
        esac
        ;;
    *)
esac
