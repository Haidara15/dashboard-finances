# Déploiement automatique d’une application R Shiny sur VPS Ubuntu (OVH) avec Docker, NGINX et CI/CD Blue/Green via GitHub Actions & GHCR (GitHub Container Registry)


Application Shiny conteneurisée et déployée sur un VPS OVHcloud via Docker, NGINX (reverse proxy) et GitHub Actions (CI/CD).  
Le déploiement se fait avec une stratégie **Blue/Green** pour des mises à jour sans interruption.  

---

## Commandes utiles à connaître

Avant de commencer, voici un mini-glossaire des options et commandes que vous verrez souvent :  

- `sudo` → exécuter la commande en tant qu’administrateur (super-utilisateur). Obligatoire pour modifier la config système.  
- `-y` → répondre automatiquement "yes" (utile pour les installations).  
- `-t` → tester la configuration (par exemple `nginx -t` vérifie que la config est valide).  
- `-p` → définir le port de publication d’un conteneur Docker (ex: `-p 3838:3838`).  
- `-v` → afficher la version d’un logiciel (`nginx -v`, `docker -v`).  
- `CTRL + O` → sauvegarder un fichier dans `nano`.  
- `CTRL + X` → quitter l’éditeur `nano`.  

---

## I Connexion au VPS

D’abord, connectez-vous à votre serveur :  

```bash
ssh username_server@ip_vps
```

- **username_server** → votre utilisateur VPS.  
- **ip_vps** → l’adresse IP de votre serveur (Exemple : 51.68.XXX.XXX).  

---

## II Préparation du VPS

### DNS  
Avant tout, assurez-vous que votre domaine pointe bien vers l’IP de votre VPS :  

```bash
dig +short Nom-de-domaine
dig +short www.Nom-de-domaine
```

Les deux doivent renvoyer l’IP de votre VPS.  

---

### 1) Mise à jour du système  

```bash
sudo apt update && sudo apt upgrade -y
```

---

### 2) Installation de Docker  

```bash
sudo apt install -y ca-certificates curl gnupg lsb-release

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

docker --version
```

---

### 3) Donner accès Docker à votre utilisateur VPS  

```bash
sudo usermod -aG docker username_server
```

Remplacez `username_server` par votre utilisateur (par ex. `haidara`).  
Déconnectez-vous puis reconnectez-vous au VPS pour appliquer.  

Vérifiez :  

```bash
groups
```

---

### 4) Installer NGINX  

```bash
sudo apt install -y nginx
nginx -v
```

---

### 5) HTTPS avec Let’s Encrypt  

```bash
sudo apt install -y certbot python3-certbot-nginx

sudo certbot --nginx -d Nom-de-domaine -d www.Nom-de-domaine
```

---

### 6) Installer yq (lecture YAML)  

On utilise **yq** dans le script *blue_green* pour lire le fichier `ports.yml`.  

```bash
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq
yq --version
```

---

### 7) Créer l’arborescence standard  

```bash
sudo mkdir -p /etc/nginx/upstreams
mkdir -p ~/configs
mkdir -p ~/temp_nginx
```

---

## III Dockerfile

Créez un fichier **Dockerfile** à la racine de votre projet :  

```Dockerfile
FROM rocker/shiny:4.1.2 

# Installer dépendances système nécessaires
RUN apt-get update && apt-get install -y     libssl-dev     libcurl4-openssl-dev     libxml2-dev     libglpk-dev  && rm -rf /var/lib/apt/lists/*

# Installer remotes
RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org')"

# Installer les packages nécessaires
RUN R -e "remotes::install_cran(c(     'shiny', 'highcharter', 'DT', 'readr', 'dplyr', 'tidyr',     'lubridate', 'scales', 'cachem', 'digest', 'htmlwidgets',     'xts', 'zoo', 'igraph'   ))"

# Supprimer tout le contenu par défaut de Shiny Server
RUN rm -rf /srv/shiny-server/*

# Copier votre application
COPY . /srv/shiny-server/

# Donner les bons droits
RUN chown -R shiny:shiny /srv/shiny-server

# Exposer le port Shiny
EXPOSE 3838

# Lancer Shiny Server
CMD ["/usr/bin/shiny-server"]
```

---

## IV Configuration NGINX

### a) Fichier de site  

Créez le fichier suivant :  

```bash
sudo nano /etc/nginx/sites-available/Nom-de-domaine
```

Collez :  

```nginx
##############################
# Upstream
##############################
upstream dashboard-finances {
    include /etc/nginx/upstreams/dashboard-finances.conf;
}

##############################
# Server HTTPS (443)
##############################
server {
    server_name m-haidara.fr www.m-haidara.fr;

    # dashboard-finances
    location /dashboard-finances/ {
        proxy_pass http://dashboard-finances/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 20d;
        proxy_buffering off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        proxy_redirect http://127.0.0.1:3845/ /dashboard-finances/;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/m-haidara.fr/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/m-haidara.fr/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

##############################
# Server HTTP (80 → HTTPS)
##############################
server {
    if ($host = www.m-haidara.fr) {
        return 301 https://$host$request_uri;
    }

    if ($host = m-haidara.fr) {
        return 301 https://$host$request_uri;
    }

    listen 80;
    server_name m-haidara.fr www.m-haidara.fr;
    return 404;
}

```

Enregistrez : `CTRL + O`, puis quittez : `CTRL + X`.  

Activez le site :  

```bash
sudo ln -s /etc/nginx/sites-available/m-haidara.fr /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

### b) Fichier upstream  

Créez :  

```bash
sudo nano /etc/nginx/upstreams/dashboard-finances.conf
```

Collez :  

```nginx
# On liste les deux ports Blue/Green
# Lors du déploiement, le script mettra à jour ce fichier en activant l’un des deux.
server 127.0.0.1:3845;   # port Blue
# server 127.0.0.1:3945; # port Green
```

---

### c) Fichier des ports  

Créez :  

```bash
nano ~/configs/ports.yml
```

Collez :  

```yaml
dashboard-finances:
  blue: 3845
  green: 3945
```

---

## V Script Blue/Green

Créez :  

```bash
nano ~/deploy_blue_green.sh
```

Collez :  

```bash
#!/bin/bash
set -e

APP_NAME="$1"

if [ -z "$APP_NAME" ]; then
  echo " Usage: $0 <app_name>"
  exit 1
fi

PORTS_FILE="/home/username_server/configs/ports.yml"

if [ ! -f "$PORTS_FILE" ]; then
  echo " Fichier des ports introuvable : $PORTS_FILE"
  exit 1
fi

BLUE_PORT=$(yq ".${APP_NAME}.blue" "$PORTS_FILE")
GREEN_PORT=$(yq ".${APP_NAME}.green" "$PORTS_FILE")

if [ -z "$BLUE_PORT" ] || [ -z "$GREEN_PORT" ]; then
  echo "Ports non définis pour l’application '$APP_NAME' dans $PORTS_FILE"
  exit 1
fi

IMAGE="ghcr.io/Haidara15/${APP_NAME}:latest"
ACTIVE_FILE="/home/username_server/${APP_NAME}_active_color.txt"
NGINX_UPSTREAM="/etc/nginx/upstreams/${APP_NAME}.conf"

if [ -f "$ACTIVE_FILE" ]; then
  ACTIVE=$(cat "$ACTIVE_FILE")
else
  ACTIVE="green"
fi

if [ "$ACTIVE" = "blue" ]; then
  NEXT="green"
  PORT=$GREEN_PORT
else
  NEXT="blue"
  PORT=$BLUE_PORT
fi

echo "Déploiement de $APP_NAME vers $NEXT (port $PORT)"

# Supprimer tout conteneur écoutant déjà sur le port ciblé
echo " Nettoyage des conteneurs utilisant le port ${PORT}..."
CONFLICTING_CONTAINER=$(docker ps --filter "publish=${PORT}" --format "{{.ID}}")
if [ -n "$CONFLICTING_CONTAINER" ]; then
  echo " Un conteneur utilise déjà le port ${PORT}. Suppression..."
  docker rm -f "$CONFLICTING_CONTAINER"
fi

# Supprimer l’ancien conteneur de cette version (si déjà existant)
docker rm -f ${APP_NAME}-${NEXT} 2>/dev/null || true

echo "Pull de la dernière image $IMAGE..."
docker pull "$IMAGE"

docker run -d \
  --name ${APP_NAME}-${NEXT} \
  -p ${PORT}:3838 \
  $IMAGE

echo "Vérification de la santé..."
for i in {1..10}; do
  if curl -fs http://localhost:${PORT}/ > /dev/null; then
    echo "Conteneur $NEXT OK"
    break
  fi
  echo "En attente..."
  sleep 2
done

echo "server 127.0.0.1:${PORT};" | sudo tee "$NGINX_UPSTREAM" > /dev/null
echo "$NEXT" > "$ACTIVE_FILE"

echo " Reload de NGINX..."
sudo systemctl reload nginx

echo "$APP_NAME déployé sans downtime vers $NEXT"
```

Rendez-le exécutable :  

```bash
chmod +x ~/deploy_blue_green.sh
```

---

## VI GitHub Actions

Créez sur GitHub le fichier `.github/workflows/deploy.yml` :  

```yaml
name: Déploiement Dashboard Finances (Docker)

on:
  push:
    branches:
      - main

jobs:
  build-and-deploy:
    name: Construction et déploiement
    runs-on: ubuntu-latest

    steps:
      - name: Récupération du dépôt
        uses: actions/checkout@v4

      - name: Connexion au GitHub Container Registry
        run: echo "${{ secrets.GHCR_PAT }}" | docker login ghcr.io -u Haidara15 --password-stdin

      - name: Construction de l’image Docker (sans cache)
        run: |
          IMAGE_NAME=ghcr.io/haidara15/dashboard-finances:latest
          docker build --no-cache -t $IMAGE_NAME .

      - name: Envoi de l’image Docker
        run: |
          IMAGE_NAME=ghcr.io/haidara15/dashboard-finances:latest
          docker push $IMAGE_NAME

      - name: Test de la connexion SSH
        run: |
          printf "%s\n" "${{ secrets.SSH_PRIVATE_KEY }}" > id_ed25519
          chmod 600 id_ed25519
          ssh -i id_ed25519 -o StrictHostKeyChecking=no ${{ secrets.VPS_USER }}@${{ secrets.VPS_HOST }} "echo Connected"

      - name: Déploiement sur le VPS (Blue-Green)
        uses: appleboy/ssh-action@v1.1.0
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script_stop: true
          script: |
            bash ~/deploy_blue_green.sh dashboard-finances

```

---

### VII Secrets GitHub Actions  

Dans votre dépôt GitHub → **Settings → Secrets and variables → Actions → New repository secret**, ajoutez les secrets suivants :  

- **`GHCR_PAT`** → un **token GitHub** permettant de pousser vos images Docker dans le registre GitHub Container Registry (GHCR).  
  Pour le générer :  
  - Allez dans **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**  
  - Cliquez sur **Generate new token (classic)**  
  - Donnez un nom (ex: `ghcr-deploy`), une durée de validité (ex: 90 jours)  
  - Cochez uniquement les droits :  
    - `write:packages`  
    - `read:packages`  
    - `delete:packages` (optionnel)  
  - Copiez le token généré et collez-le dans le champ `GHCR_PAT` sur GitHub.  

- **`VPS_HOST`** → l’adresse IP de votre VPS (par ex: `ip_vps`).  

- **`VPS_USER`** → l’utilisateur de votre VPS (par ex: `username_server`).  

- **`SSH_PRIVATE_KEY`** → le **contenu de votre clé privée SSH** qui permet à GitHub Actions de se connecter automatiquement à votre VPS.  

  Pour la générer :  
  ```bash
  ssh-keygen -t ed25519 -C "votre-email@example.com" -f ~/.ssh/github_actions_key

  Cela crée deux fichiers dans `~/.ssh/` :

- `github_actions_key` → clé privée (**ne jamais partager**)  
- `github_actions_key.pub` → clé publique (à copier dans le VPS)  

Copier la clé publique sur le VPS :  
```bash
ssh-copy-id -i ~/.ssh/github_actions_key.pub username_server@ip_vps

````

Vérifier que la connexion SSH fonctionne sans mot de passe :

```bash

ssh -i ~/.ssh/github_actions_key username_server@ip_vps

````

Ensuite, ouvrir la clé privée pour copier son contenu :

```bash

cat ~/.ssh/github_actions_key

````

Copier tout le contenu affiché et le coller dans le secret SSH_PRIVATE_KEY sur GitHub.


---

## VIII Workflow complet (après modification locale)

Une fois tout configuré, le cycle est le suivant :  

```bash
# Modifier votre app (app.R, styles.css, etc.)
git add .
git commit -m "Nouvelle mise à jour"
git push origin main
```

Dès que vous poussez sur **main** :  
1. GitHub Actions construit une nouvelle image Docker.  
2. L’image est poussée sur GitHub Container Registry (GHCR).  
3. Le workflow se connecte en SSH à votre VPS.  
4. Le script `deploy_blue_green.sh` déploie la nouvelle version sur le port libre (Blue ou Green).  
5. NGINX bascule automatiquement le trafic.  

Résultat : mise à jour sans interruption de service 
