#!/bin/bash

case $1 in
    certbot)
        /root/.local/bin/certbot renew --post-hook "systemctl reload nginx"
        ;;
    borgmatic)
        /root/.local/bin/borgmatic --verbosity -1 --syslog-verbosity 1
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
        ;;
    *)
        ;;
esac