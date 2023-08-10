#!/bin/bash
SRVHOSTNAME=$(hostname -s)
export SHORT_HOSTNAME=$(hostname -s)
TG_CHADID=$(cat /root/.telegram.secrets | grep CHATID | cut -d\= -f2 | sed 's/\"//g')
TG_TOKEN=$(cat /root/.telegram.secrets | grep TOKEN | cut -d\= -f2 | sed 's/\"//g')

case $1 in
    certbot)
        /root/.local/bin/certbot renew --post-hook "systemctl reload nginx"
        # apprise -vv -t "[${SRVHOSTNAME^^}] - Certbot" -b "Certbot renew successfull" tgram://${TG_TOKEN}/${TG_CHADID}/
        ;;
    borgmatic)
        /root/.local/bin/borgmatic --verbosity -1 --syslog-verbosity 1
        # apprise -vv -t "[${SRVHOSTNAME^^}] - Borgmatic" -b "Borg backup successfully run" tgram://${TG_TOKEN}/${TG_CHADID}/
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
        # apprise -vv -t "[${SRVHOSTNAME^^}] - GeoIP Legacy Updater" -b "GeoIP database successfully updated" tgram://${TG_TOKEN}/${TG_CHADID}/
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

        # systemctl restart fail2ban.service
        # if [[ $? -eq 0 ]]; then
        #     apprise -vv -t "[${SRVHOSTNAME^^}] - Fail2ban Ignore IP" -b "IgnoreIP successfully updated for Fail2ban jail" tgram://${TG_TOKEN}/${TG_CHADID}/
        # fi
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
        # if [[ $? -eq 0 ]]; then
        #     # apprise -vv -t "[${SRVHOSTNAME^^}] - CloudflareRealIP" -b "Cloudflare Real IP updated successfully !" tgram://${TG_TOKEN}/${TG_CHADID}/
        # fi
        ;;
    convertwebpavif)
        if [[ ! -z $2 ]]; then
            echo "# Working on $2"
            WEBSITE="/opt/websites/${2}.env"
            DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
            HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
            WEB_PATH="${HOME_PATH}/web"
            UPLOADS_PATH="${WEB_PATH}/wp-content/uploads"
            OWNER=$(stat -c "%U" ${WEB_PATH})
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
            chown -R ${OWNER}:www-data ${UPLOADS_PATH}
        else
            for WEBSITE in $(ls /opt/websites/*.env)
            do
                DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
                echo "# Working on $DOMAIN"
                HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
                WEB_PATH="${HOME_PATH}/web"
                UPLOADS_PATH="${WEB_PATH}/wp-content/uploads"
                OWNER=$(stat -c "%U" ${WEB_PATH})
                if [[ -f ${WEB_PATH}/wp-config.php ]]; then
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
                    chown -R ${OWNER}:www-data ${UPLOADS_PATH}
                fi
            done
        fi
        # apprise -vv -t "[${SRVHOSTNAME^^}] - WEBPAVIF" -b "Webp & Avif Images conversion Success !" tgram://${TG_TOKEN}/${TG_CHADID}/
        ;;
    fixperms)
        for WEBSITE in $(ls /opt/websites/*.env)
        do
            DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
            HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
            WEB_PATH="${HOME_PATH}/web"
            OWNER=$(stat -c "%U" ${WEB_PATH})
            if [[ -f ${WEB_PATH}/wp-config.php ]]; then
                echo ${DOMAIN}
                find ${WEB_PATH} -type f -exec chmod 644 '{}' \;
                chmod 755 ${WEB_PATH}
                chmod 755 ${WEB_PATH}/wp-admin ${WEB_PATH}/wp-includes ${WEB_PATH}/wp-content ${WEB_PATH}/wp-content/themes ${WEB_PATH}/wp-content/plugins ${WEB_PATH}/wp-content/uploads
                chmod 640 ${WEB_PATH}/wp-config.php
            fi
        done
        ;;
    wpconstant)
        for WEBSITE in $(ls /opt/websites/*.env)
        do
            DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
            HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
            WEB_PATH="${HOME_PATH}/web"
            OWNER=$(stat -c "%U" ${WEB_PATH})
            if [[ -f ${WEB_PATH}/wp-config.php ]]; then
                echo "# ${DOMAIN}"
                case $2 in
                    deleteconstant)
                        sudo -u ${OWNER} wp --path=${WEB_PATH} config delete $3
                        ;;
                    constant)
                        sudo -u ${OWNER} wp --path=${WEB_PATH} config set $3 "$4"
                        ;;
                    plugin)
                        sudo -u ${OWNER} wp --path=${WEB_PATH} plugin $3
                        ;;
                    redis)
                        sudo -u ${OWNER} wp --path=${WEB_PATH} config set WP_CACHE_KEY_SALT "redis_${DOMAIN}"
                        sudo -u ${OWNER} wp --path=${WEB_PATH} redis enable
                        sudo -u ${OWNER} wp --path=${WEB_PATH} redis update-dropin
                        ;;
                    custom)
                        sudo -u ${OWNER} wp --path=${WEB_PATH} $3
                        ;;
                    *)
                esac
                
            fi
        done
        ;;
    robotstxt)
        for WEBSITE in $(ls /opt/websites/*.env)
        do
            DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
            HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
            WEB_PATH="${HOME_PATH}/web"
            OWNER=$(stat -c "%U" ${WEB_PATH})
            if [[ -d ${WEB_PATH} ]]; then
                if [[ ! -f ${WEB_PATH}/robots.txt ]]; then
                    echo "# Generating robots.txt for $DOMAIN"
                    touch ${WEB_PATH}/robots.txt
                    wget -q https://raw.githubusercontent.com/bilyboy785/public/main/nginx/robots.txt -O ${WEB_PATH}/robots.txt
                fi
            fi
        done
        ;;
    websitedown)
        DOMAIN=$2
        sed -i 's/root\ \ .*/root\ \/var\/www\/html\/down.bldwebagency.fr;/g' /etc/nginx/sites-enabled/${DOMAIN}.conf
        systemctl reload nginx.service
        ;;
    cloudflarebanip)
        function elog {
            echo "[$(date '+%Y%m%d-%H%M%S')] - Cloudflare Ban IP - $1 successfuly $2 for account $3" >> /var/log/fail2ban.cloudflare.log
            echo "[$(date '+%Y%m%d-%H%M%S')] - Cloudflare Ban IP - $1 successfuly $2 for account $3"
        }
        CF_EMAIL=$(cat ~/.cloudflare-creds | grep email | cut -d\= -f2 | sed 's/\ //g')
        CF_APIKEY=$(cat ~/.cloudflare-creds | grep api_key | cut -d\= -f2 | sed 's/\ //g')
        IP=$3
        ACTION=$2
        case $ACTION in
            ban)
                BAN_BLDWEBAGENCY=$(/usr/bin/curl -sX POST "https://api.cloudflare.com/client/v4/accounts/c05ed148df8541c4a08304f3bf28ac26/rules/lists/0dce2ea32d0f486880e8d4edf535eab4/items" \
                -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" --data '[{"ip":"'${IP}'"}]' | /root/.local/bin/jq -r '.success')
                if [[ "$BAN_BLDWEBAGENCY" == "true" ]]; then
                    elog "$IP" "ban" "BLDWebAgency"
                fi
                BAN_DTS=$(/usr/bin/curl -sX POST "https://api.cloudflare.com/client/v4/accounts/3eda1db40e33ad381b6757dffe5aceb5/rules/lists/82f659b4dbe34791b600d334dd34710b/items" \
                -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" --data '[{"ip":"'${IP}'"}]' | /root/.local/bin/jq -r '.success')
                if [[ "$BAN_DTS" == "true" ]]; then
                    elog "$IP" "ban" "DTS"
                fi
                ;;
            unban)
                ITEM_ID=$(/usr/bin/curl -sX GET "https://api.cloudflare.com/client/v4/accounts/c05ed148df8541c4a08304f3bf28ac26/rules/lists/0dce2ea32d0f486880e8d4edf535eab4/items" \
                        -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | /root/.local/bin/jq '.result[] | select(.ip == "'${IP}'")' | /root/.local/bin/jq -r '.id')
                DELETE_BLDWEBAGENCY=$(/usr/bin/curl -sX DELETE "https://api.cloudflare.com/client/v4/accounts/c05ed148df8541c4a08304f3bf28ac26/rules/lists/0dce2ea32d0f486880e8d4edf535eab4/items" \
                        -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" --data '{"items":[{"id":"'$ITEM_ID'"}]}' | /root/.local/bin/jq -r '.success')
                if [[ "$DELETE_BLDWEBAGENCY" == "true" ]]; then
                    elog "$IP" "unban" "BLDWebAgency"
                fi
                ITEM_ID=$(/usr/bin/curl -sX GET "https://api.cloudflare.com/client/v4/accounts/3eda1db40e33ad381b6757dffe5aceb5/rules/lists/82f659b4dbe34791b600d334dd34710b/items" \
                        -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | /root/.local/bin/jq '.result[] | select(.ip == "'${IP}'")' | /root/.local/bin/jq -r '.id')
                DELETE_DTS=$(/usr/bin/curl -sX DELETE "https://api.cloudflare.com/client/v4/accounts/3eda1db40e33ad381b6757dffe5aceb5/rules/lists/82f659b4dbe34791b600d334dd34710b/items" \
                        -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" --data '{"items":[{"id":"'$ITEM_ID'"}]}' | /root/.local/bin/jq -r '.success')
                if [[ "$DELETE_DTS" == "true" ]]; then
                    elog "$IP" "unban" "DTS"
                fi
                ;;
            *)
                ;;
        esac
        ;;
    cfcheckip)
        IP=$2
        CF_EMAIL=$(cat ~/.cloudflare-creds | grep email | cut -d\= -f2 | sed 's/\ //g')
        CF_APIKEY=$(cat ~/.cloudflare-creds | grep api_key | cut -d\= -f2 | sed 's/\ //g')
        ITEM_ID=$(/usr/bin/curl -sX GET "https://api.cloudflare.com/client/v4/accounts/c05ed148df8541c4a08304f3bf28ac26/rules/lists/0dce2ea32d0f486880e8d4edf535eab4/items" \
                        -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | /root/.local/bin/jq '.result[] | select(.ip == "'${IP}'")' | /root/.local/bin/jq -r '.id')
        ITEM_ID=$(/usr/bin/curl -sX GET "https://api.cloudflare.com/client/v4/accounts/3eda1db40e33ad381b6757dffe5aceb5/rules/lists/82f659b4dbe34791b600d334dd34710b/items" \
                        -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_APIKEY}" -H "Content-Type: application/json" | /root/.local/bin/jq '.result[] | select(.ip == "'${IP}'")' | /root/.local/bin/jq -r '.id')
        ;;
    healthcheck)
        for site in $(ls /var/www/html)
        do
            if [[ -f /var/www/html/$site/web/wp-config.php ]]; then
                FULL_PATH="/var/www/html/$site/web"
                OWNER=$(stat -c "%U" ${FULL_PATH})
                SITE_NAME=$(echo $site | sed 's/www\.//g')
                FTP_DOMAIN=$(echo $site | sed 's/www\.//g' | sed 's/demo1\.//g' | sed 's/demo2\.//g' | sed 's/demo3\.//g' | sed 's/dev\.//g')
                HEALTHCHECK_SLUG_TMP=$(echo $site | sed 's/\.//g')
                HEALTHCHECK_SLUG="wp-cron-${HEALTHCHECK_SLUG_TMP}"
                echo "Updating cron for $SITE_NAME"
                HC_PING_URL=$(curl -s -X GET --header "X-Api-Key: PFyzt8uS_se--zYpr5KcJlendT-V5cek" "https://healthchecks.bldwebagency.fr/api/v3/checks/" | jq -r '.checks[] | select(.name | contains("'$SITE_NAME'"))' | jq -r '.ping_url')
                if [[ -z ${HC_PING_URL} ]]; then
                    echo "$site --> Healthcheck not found, creating..."
                    HC_PING_URL=$(curl -s -X POST "https://healthchecks.bldwebagency.fr/api/v3/checks/" --header "X-Api-Key: PFyzt8uS_se--zYpr5KcJlendT-V5cek" \
                            --data '{"name": "[WP Cron] '${FTP_DOMAIN}'", "slug": "'${HEALTHCHECK_SLUG}'", "tags": "'${SHORT_HOSTNAME}'", "timeout": 900, "grace": 1800, "channels": "*"}' | jq -r '.ping_url')
                    echo "  Ping URL : $HC_PING_URL"
                fi
                echo -e "MAILTO=\"\"\n*/15 * * * *  RID=\`uuidgen\` && curl -fsS -m 10 --retry 5 -o /dev/null ${HC_PING_URL}/start?rid=\$RID && /usr/local/bin/wp --path=${FULL_PATH} cron event run --due-now && curl -fsS -m 10 --retry 5 -o /dev/null ${HC_PING_URL}?rid=\$RID" | crontab -u ${OWNER} -
            fi
        done
        ;;
    updown)
        for site in $(ls /var/www/html)
        do
            SITE_NAME=$(echo $site | sed 's/www\.//g')
            FTP_DOMAIN=$(echo $site | sed 's/www\.//g' | sed 's/demo1\.//g' | sed 's/demo2\.//g' | sed 's/demo3\.//g' | sed 's/dev\.//g')
            UPDOWN_TOKEN=$(curl -s "https://updown.io/api/checks\?api-key\=Vy4Dw9BD35jU7eFMzWwg" | jq '.[] | select(.alias | contains("'${FTP_DOMAIN}'"))' | jq -r '.token')
            if [[ -z ${UPDOWN_URL} ]]; then
                echo "Site already on Updown : https://updown.io/${UPDOWN_TOKEN}"
            fi
            # HEALTHCHECK_SLUG_TMP=$(echo $site | sed 's/\.//g')
            # HEALTHCHECK_SLUG="wp-cron-${HEALTHCHECK_SLUG_TMP}"
            # echo "Updating cron for $SITE_NAME"
            # HC_PING_URL=$(curl -s -X GET --header "X-Api-Key: PFyzt8uS_se--zYpr5KcJlendT-V5cek" "https://healthchecks.bldwebagency.fr/api/v3/checks/" | jq -r '.checks[] | select(.name | contains("'$SITE_NAME'"))' | jq -r '.ping_url')
            # if [[ -z ${HC_PING_URL} ]]; then
            #     echo "$site --> Healthcheck not found, creating..."
            #     HC_PING_URL=$(curl -s -X POST "https://healthchecks.bldwebagency.fr/api/v3/checks/" --header "X-Api-Key: PFyzt8uS_se--zYpr5KcJlendT-V5cek" \
            #             --data '{"name": "[WP Cron] '${FTP_DOMAIN}'", "slug": "'${HEALTHCHECK_SLUG}'", "tags": "'${SHORT_HOSTNAME}'", "timeout": 900, "grace": 1800, "channels": "*"}' | jq -r '.ping_url')
            #     echo "  Ping URL : $HC_PING_URL"
            # fi
            # echo -e "MAILTO=\"\"\n*/15 * * * *  RID=\`uuidgen\` && curl -fsS -m 10 --retry 5 -o /dev/null ${HC_PING_URL}/start?rid=\$RID && /usr/local/bin/wp --path=${FULL_PATH} cron event run --due-now && curl -fsS -m 10 --retry 5 -o /dev/null ${HC_PING_URL}?rid=\$RID" | crontab -u ${OWNER} -
        done


        
    *)
        ;;
esac