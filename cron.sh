#!/bin/bash
SRVHOSTNAME=$(hostname -s)
TG_CHADID=$(cat /root/.telegram.secrets | grep CHATID | cut -d\= -f2 | sed 's/\"//g')
TG_TOKEN=$(cat /root/.telegram.secrets | grep TOKEN | cut -d\= -f2 | sed 's/\"//g')

case $1 in
    certbot)
        /root/.local/bin/certbot renew --post-hook "systemctl reload nginx"
        apprise -vv -t "[${SRVHOSTNAME^^}] - Certbot" -b "Certbot renew successfull" tgram://${TG_TOKEN}/${TG_CHADID}/
        ;;
    borgmatic)
        /root/.local/bin/borgmatic --verbosity -1 --syslog-verbosity 1
        apprise -vv -t "[${SRVHOSTNAME^^}] - Borgmatic" -b "Borg backup successfully run" tgram://${TG_TOKEN}/${TG_CHADID}/
        ;;
    geoiplegacyupdater)
        COUNTRY_IPV4="https://dl.miyuru.lk/geoip/maxmind/country/maxmind4.dat.gz"
        COUNTRY_IPV6="https://dl.miyuru.lk/geoip/maxmind/country/maxmind6.dat.gz"
        CITY_IPV4="https://dl.miyuru.lk/geoip/maxmind/city/maxmind4.dat.gz"
        CITY_IPV6="https://dl.miyuru.lk/geoip/maxmind/city/maxmind6.dat.gz"
        OUTPUT_PATH="/etc/nginx/geoip"

        if [[ ! -d ${OUTPUT_PATH} ]]; then
            mkdir -p ${OUTPUT_PATH}
        fi

        case $2 in
            ipv4)
                wget -q -O ${OUTPUT_PATH}/geolite-country-ipv4.dat.gz ${COUNTRY_IPV4}
                wget -q -O ${OUTPUT_PATH}/geolite-city-ipv4.dat.gz ${CITY_IPV4}
                ;;
            ipv6)
                wget -q -O ${OUTPUT_PATH}/geolite-country-ipv6.dat.gz ${COUNTRY_IPV6}
                wget -q -O ${OUTPUT_PATH}/geolite-city-ipv6.dat.gz ${CITY_IPV6}
                ;;
            *)
                wget -q -O ${OUTPUT_PATH}/geolite-country-ipv6.dat.gz ${COUNTRY_IPV6}
                wget -q -O ${OUTPUT_PATH}/geolite-city-ipv6.dat.gz ${CITY_IPV6}
                wget -q -O ${OUTPUT_PATH}/geolite-country-ipv4.dat.gz ${COUNTRY_IPV4}
                wget -q -O ${OUTPUT_PATH}/geolite-city-ipv4.dat.gz ${CITY_IPV4}
                ;;
        esac

        for GZIP_FILE in $(find ${OUTPUT_PATH} -type f -name "*.gz")
        do
            gunzip -f $GZIP_FILE
        done
        apprise -vv -t "[${SRVHOSTNAME^^}] - GeoIP Legacy Updater" -b "GeoIP database successfully updated" tgram://${TG_TOKEN}/${TG_CHADID}/
        ;;
    fail2banignoreip)
        TRUSTED_IP="163.172.53.51 163.172.51.134 163.172.33.112"

        IGNOREIP_LIST_TMP="${TRUSTED_IP}"
        
        for IPV4 in $(curl -s https://www.cloudflare.com/ips-v4)
        do
            IGNOREIP_LIST_TMP="${IGNOREIP_LIST_TMP} ${IPV4}"
        done

        for IPV6 in $(curl -s https://www.cloudflare.com/ips-v6)
        do
            IGNOREIP_LIST_TMP="${IGNOREIP_LIST_TMP} ${IPV6}"
        done

        IGNOREIP_LIST=$(echo ${IGNOREIP_LIST_TMP} | sed 's/\//\\\//g')
        
        sed -i "s/ignoreip.*/ignoreip\ =\ ${IGNOREIP_LIST}/g" /etc/fail2ban/jail.local

        systemctl restart fail2ban.service
        if [[ $? -eq 0 ]]; then
            apprise -vv -t "[${SRVHOSTNAME^^}] - Fail2ban Ignore IP" -b "IgnoreIP successfully updated for Fail2ban jail" tgram://${TG_TOKEN}/${TG_CHADID}/
        fi
        ;;
    cloudflarerealip)
        REALIP="# Updated $(date '+%Y-%m-%d %H:%M:%S')\n"
        REALIP="$REALIP\n"
        for IPV4 in $(curl -s https://www.cloudflare.com/ips-v4)
        do
            REALIP="${REALIP}set_real_ip_from ${IPV4};\n"
            cat /etc/crowdsec/parsers/s02-enrich/whitelist.yaml | grep ${IPV4} > /dev/null 2>&1
            if [[ ! $? -eq 0 ]]; then
                yq -i '.whitelist.ip += "'${IPV4}'"' /etc/crowdsec/parsers/s02-enrich/whitelist.yaml
            fi
        done

        for IPV6 in $(curl -s https://www.cloudflare.com/ips-v6)
        do
            REALIP="${REALIP}set_real_ip_from ${IPV6};\n"
            cat /etc/crowdsec/parsers/s02-enrich/whitelist.yaml | grep ${IPV6} > /dev/null 2>&1
            if [[ ! $? -eq 0 ]]; then
                yq -i '.whitelist.ip += "'${IPV6}'"' /etc/crowdsec/parsers/s02-enrich/whitelist.yaml
            fi
        done

        REALIP="${REALIP}\n"
        REALIP="${REALIP}real_ip_header CF-Connecting-IP;\n"
        REALIP="${REALIP}#real_ip_header X-Forwarded-For;"

        echo -e ${REALIP} > /etc/nginx/snippets/cloudflare.conf

        systemctl reload nginx.service
        if [[ $? -eq 0 ]]; then
            apprise -vv -t "[${SRVHOSTNAME^^}] - CloudflareRealIP" -b "Cloudflare Real IP updated successfully !" tgram://${TG_TOKEN}/${TG_CHADID}/
        fi
        ;;
    convertwebpavif)
        for WEBSITE in $(ls /opt/websites/*.env)
        do
            DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
            HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
            WEB_PATH="${HOME_PATH}/web"
            OWNER=$(stat -c "%U" ${WEB_PATH})
            if [[ -f ${WEB_PATH}/wp-config.php ]]; then
                UPLOADS_PATH="${WEB_PATH}/wp-content/uploads"
                for IMG in $(find $UPLOADS_PATH -type f -name '*.jpg' -or -name '*.jpeg' -or -name '*.png' -or -name '*.JPG' -or -name '*.JPEG' -or -name '*.PNG')
                do
                        IMG_FILENAME=$(basename ${IMG})
                        IMG_DIRNAME=$(dirname ${IMG})
                        NEW_NAME_WEBP="${IMG_DIRNAME}/${IMG_FILENAME}.webp"
                        NEW_NAME_AVIF="${IMG_DIRNAME}/${IMG_FILENAME}.avif"
                        if [[ ! -f ${NEW_NAME_WEBP} ]]; then
                                echo "   - ${NEW_NAME_WEBP}"
                                cwebp -quiet -q 75 ${IMG} -o ${NEW_NAME_WEBP} > /dev/null 2>&1
                        fi
                        if [[ ! -f ${NEW_NAME_AVIF} ]]; then
                                echo "   - ${NEW_NAME_AVIF}"
                                convert -quiet -quality 75 ${IMG} ${NEW_NAME_AVIF} > /dev/null 2>&1
                        fi
                done
            fi
            chown -R ${OWNER}:www-data ${UPLOADS_PATH}
        done
        apprise -vv -t "[${SRVHOSTNAME^^}] - WEBPAVIF" -b "Webp & Avif Images conversion Success !" tgram://${TG_TOKEN}/${TG_CHADID}/
        ;;
    fixperms)
        for WEBSITE in $(ls /opt/websites/*.env)
        do
            DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
            HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
            WEB_PATH="${HOME_PATH}/web"
            OWNER=$(stat -c "%U" ${WEB_PATH})
            if [[ -f ${WEB_PATH}/wp-config.php ]]; then
                echo ${WEB_PATH}
                # find ${WEB_PATH} -type f -exec chmod 644 '{}' \; && find ${WEB_PATH} -type d -exec chmod 755 '{}' \;
            fi
        done
        ;;
    websitedown)
        DOMAIN=$2
        sed -i 's/root\ \ .*/root\ \/var\/www\/html\/down.bldwebagency.fr;/g' /etc/nginx/sites-enabled/${DOMAIN}.conf
        systemctl reload nginx.service
        ;;
    *)
        ;;
esac