#!/bin/bash

case $1 in
    certbot)
        /root/.local/bin/certbot renew --post-hook "systemctl reload nginx"
        ;;
    borgmatic)
        /root/.local/bin/borgmatic --verbosity -1 --syslog-verbosity 1
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
esac