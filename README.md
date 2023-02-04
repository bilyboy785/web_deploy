# Web Deployer

Easy script to deploy Web Stack

## Website_deploy
### Init du serveur

```
git clone https://github.com/bilyboy785/web_deploy.git /opt/web_deploy && ln -s /opt/web_deploy/web_deploy.sh $HOME/.local/bin/web_deploy && chmod +x /opt/web_deploy/web_deploy.sh
bash $HOME/.local/bin/web_deploy -i
```

### Deploiement d'un site
```
web_deploy -d SERVER_NAME PHP_VERSION
    - web_deploy -d monsite.com 8.2
```