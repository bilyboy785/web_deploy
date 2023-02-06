# Web Deployer

Easy script to deploy Web Stack

## Website_deploy
### Init du serveur

```
git clone https://github.com/bilyboy785/web_deploy.git /opt/web_deploy && mkdir -p $HOME/.local/bin && ln -s /opt/web_deploy/web_deploy.sh $HOME/.local/bin/web_deploy && chmod +x /opt/web_deploy/web_deploy.sh
bash $HOME/.local/bin/web_deploy -i
```

### Deploiement d'un site
```
web_deploy -d SERVER_NAME PHP_VERSION
    web_deploy -d monsite.com 8.2
```

### Gestion des volumes via LVM

```
apt install lvm2 -y
systemctl enable lvm2-lvmetad
```

#### Création d'un nouveau volume logique
```
pvcreate /dev/sda
vgcreate vg_data /dev/sda
lvcreate -l 100%FREE -n lv_web vg_data
```

#### Partitionnement et montage du volume
```
mkfs.ext4 /dev/vg_data/lv_web
mount /dev/vg_data/lv_web /var/www/html
echo '/dev/mapper/vg_data-lv_web /var/www/html ext4 defaults,nofail 0 0' >> /etc/fstab
```

#### Ajout de disque et extension du volume
```
pvcreate /dev/sdb
vgextend web /dev/sdb
lvextend -L+5G /dev/mapper/vg_data-lv_web
resize2fs /dev/mapper/vg_data-lv_web
df -h /var/www/html
```