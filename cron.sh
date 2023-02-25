#!/bin/bash
SRVHOSTNAME=$(hostname -s)
TG_CHADID=$(cat /root/.telegram.secrets | grep CHATID | cut -d\= -f2)
TG_TOKEN=$(cat /root/.telegram.secrets | grep TOKEN | cut -d\= -f2)

case $1 in
    certbot)
        /root/.local/bin/certbot renew --post-hook "systemctl reload nginx"
        docker run ghcr.io/kha7iq/pingme:latest telegram --token '5629037872:AAEJrIAlTghzp6X86GXx0HOk8Mlkm_EO5KU' --channel '19379381' --title "[${SRVHOSTNAME^^}] - Certbot" --msg "Certbot renew successfull"
        ;;
    borgmatic)
        /root/.local/bin/borgmatic --verbosity -1 --syslog-verbosity 1
        docker run ghcr.io/kha7iq/pingme:latest telegram --token '5629037872:AAEJrIAlTghzp6X86GXx0HOk8Mlkm_EO5KU' --channel '19379381' --title "[${SRVHOSTNAME^^}] - Borgmatic" --msg "Borg backup successfully run"
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
        docker run ghcr.io/kha7iq/pingme:latest telegram --token "${TG_TOKEN}" --channel "${TG_CHADID}" --title "[<b>${SRVHOSTNAME^^}</b>] - GeoIP Legacy Updater" --msg "GeoIP database successfully updated"
        ;;
    cloudflarerealip)
        REALIP="# Updated $(date '+%Y-%m-%d %H:%M:%S')\n"
        REALIP="$REALIP\n"
        for IPV4 in $(curl -s https://www.cloudflare.com/ips-v4)
        do
            REALIP="${REALIP}set_real_ip_from ${IPV4};\n"
        done

        for IPV6 in $(curl -s https://www.cloudflare.com/ips-v6)
        do
            REALIP="${REALIP}set_real_ip_from ${IPV6};\n"
        done

        REALIP="${REALIP}\n"
        REALIP="${REALIP}real_ip_header CF-Connecting-IP;\n"
        REALIP="${REALIP}#real_ip_header X-Forwarded-For;"

        echo -e ${REALIP} > /etc/nginx/snippets/cloudflare.conf

        systemctl reload nginx.service
        if [[ $? -eq 0 ]]; then
            docker run ghcr.io/kha7iq/pingme:latest telegram --token '5629037872:AAEJrIAlTghzp6X86GXx0HOk8Mlkm_EO5KU' --channel '19379381' --title "[${SRVHOSTNAME^^}] - CloudflareRealIP" --msg "Cloudflare Real IP updated successfully !"
        fi
        ;;
    convertwebpavif)
        for WEBSITE in $(ls /opt/websites/*.env)
        do
            DOMAIN=$(cat $WEBSITE | grep PRIMARY_DOMAIN | cut -d\= -f2)
            HOME_PATH=$(cat $WEBSITE | grep HOME_PATH | cut -d\= -f2)
            WEB_PATH="${HOME_PATH}/web"
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
        done
        docker run ghcr.io/kha7iq/pingme:latest telegram --token '5629037872:AAEJrIAlTghzp6X86GXx0HOk8Mlkm_EO5KU' --channel '19379381' --title "[${SRVHOSTNAME^^}] - WEBPAVIF" --msg "Webp & Avif Images conversion Success !"
        ;;
    websitedown)
        DOMAIN=$2
        sed -i 's/root\ \ .*/root\ \/var\/www\/html\/down.bldwebagency.fr;/g' /etc/nginx/sites-enabled/${DOMAIN}.conf
        systemctl reload nginx.service
        ;;
    *)
        ;;
esac