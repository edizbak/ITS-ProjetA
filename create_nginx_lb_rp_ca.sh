#!/bin/bash
echo "Nous commençons à déployer NGINX pour Debian"
sudo apt install curl gnupg2 ca-certificates lsb-release debian-archive-keyring
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | sudo tee /etc/apt/preferences.d/99nginx
sudo apt update
sudo apt install nginx
echo "L'installation de NGINX est fini!"

echo "Configuration de LoadBalancer, Reverse Proxy et de Certificat Authosigné"

echo "Etape 1. On comence avec LoadBalancer, on configure fichier nginx.conf"
# On se deplace ver le dosier de fichier nginx.conf
cd /etc/nginx
# Il y a 2 instances de la même application qui tournent sur VM#2 et VM#3. 
# On ajoute les adresses des deux serveurs dans l'upstream. Le serveur auquel une requête est envoyée est déterminé à partir
# de l'adresse IP du client. La directive IP_hash garantit que les requêtes provenant de la même adresse parviennent au même serveur, 
# sauf si celui-ci n'est pas disponible. Toutes les demandes sont transmises au groupe de serveurs "mediawiki", et Nginx applique 
# la répartition de charge HTTP pour distribuer les demandes.
sed -i -E '14 a\ ' nginx.conf
sed -i -E '15 s/[[:space:]]*/    upstream mediawiki {/' nginx.conf
sed -i -E '15 a\ ' nginx.conf
sed -i -E '16 s/[[:space:]]*/        ip_hash;/' nginx.conf
sed -i -E '16 a\ ' nginx.conf
sed -i -E '17 s/[[:space:]]*/        server 192.168.99.31:80;/' nginx.conf
sed -i -E '17 a\ ' nginx.conf
sed -i -E '18 s/[[:space:]]*/        server 192.168.99.32:80;/' nginx.conf
# Avec "backup" nous ajoutons en mode desactivé une chaîne qui peut être activée ultérieurement si nécessaire en manuel. 
# Cela permet de mettre un serveur en réserve et d'effectuer toutes les requets avec un seul serveur.
# Le serveur backup sera utilisée en cas de défaillance du serveur principal ; 
sed -i -E '18 a\ ' nginx.conf
sed -i -E '19 s/[[:space:]]*/#        server 192.168.99.32:80 backup;/' nginx.conf
sed -i -E '19 a\ ' nginx.conf
sed -i -E '20 s/[[:space:]]*/    }/' nginx.conf

echo "Etape 2.  On continue de confuguré reverse proxy..."
# On se deplace ver le dosier de fichier default.conf
cd /etc/nginx/conf.d 
# on fait la redirection du location / vers proxy_pass /mediawiki
sed -i -E '3 s/.+/#     server_name  localhost;/' default.conf
sed -i -E '7 a\ ' default.conf
sed -i -E '8 s/[[:space:]]*/        proxy_pass http:\/\/mediawiki;/' default.conf
sed -i -E '9 s/[[:space:]]*|.+/#        root   \/usr\/share\/nginx\/html;/' default.conf
sed -i -E '10 s/[[:space:]]*|.+/#        index  index.html index.htm;/' default.conf

echo "Etape 3. Creation des Clé privée, CSR (Certificate Signing Request) et Certificat auto-signé."
# Avant de configurer le serveur https, nous devons préparer une clé privée, 
# une demande de signature de certificat (CSR) et un certificat signé avec sa propre clé privée.
# Nous créons la clé privée et la CSR (Certificate Signing Request) à l'aide d'une seule commande 
# Nous voulons que notre clé privée ne soit pas chiffrée, nous pouvons ajouter l'option -nodes
# Avec help -subj, nous pouvons fournir des réponses aux questions interactives 
# nécessaires pour obtenir la clé privée et le CSR.
openssl req -newkey rsa:2048 -nodes -keyout /etc/ssl/private/domain.key -out /etc/ssl/domain.csr -subj "/C=FR/ST=Lyon/O=Thenuumfactory/emailAddress=kamerton@hotmail.com"
# Un certificat auto-signé est un certificat signé avec sa propre clé privée. Il peut être utilisé
# pour crypter des données aussi bien que les certificats signés par l'autorité de certification, 
# mais un avertissement indiquant que le certificat n'est pas fiable s'affichera à l'écran.
openssl req -key /etc/ssl/private/domain.key -new -x509 -days 365 -out /etc/ssl/certs/domain.crt -subj "/C=FR/ST=Lyon/O=Thenuumfactory/emailAddress=kamerton@hotmail.com"
# Pour des raisons de sécurité, nous devons conserver les droits 
# au minimum requis pour assurer la fonction du serveur https
echo "Configuration des drois pour fichier"
chmod 600 /etc/ssl/private/domain.key
chmod 644 /etc/ssl/domain.csr
chmod 644 /etc/ssl/certs/domain.crt

echo "Etap 4. Configuration de serveur https"
# On se deplace ver le dosier de fichier default.conf, On ajoute listen 443 ssl.
# Pour minimiser le nombre d'opérations  SSL handshake est econimiser resource CPU:
# 1) on a activer les connexions keepalive et augmenter timeouts pour envoyer plusieurs demandes via une seule connexion;
# 2) réutiliser les paramètres de la session SSL afin d'éviter les négociations SSL pour les connexions parallèles et ultérieures.
# On sauvgarde ssl_certificate et ssl_certificate_key dans le repertoir /etc/ssl. On sélectionne les protocoles et ciphers à supporter dans ssl_protocols et ssl_ciphers.
cd /etc/nginx/conf.d 
sed -i -E '2 a\ ' default.conf
sed -i -E '3 s/[[:space:]]*/    listen       443 ssl;/' default.conf
sed -i -E '3 a\ ' default.conf
sed -i -E '4 s/[[:space:]]*/    keepalive_timeout 70;/' default.conf    
sed -i -E '4 a\ ' default.conf    
sed -i -E '5 a\ ' default.conf
sed -i -E '6 s/[[:space:]]*/    ssl_protocols TLSv1.2 TLSv1.3;/' default.conf
sed -i -E '6 a\ ' default.conf 
sed -i -E '7 s/[[:space:]]*/    ssl_ciphers AES128-SHA:AES256-SHA:RC4-SHA:DES-CBC3-SHA:RC4-MD5;/' default.conf  
sed -i -E '7 a\ ' default.conf 
sed -i -E '8 s/[[:space:]]*/    ssl_certificate \/etc\/ssl\/certs\/domain.crt;/' default.conf  
sed -i -E '8 a\ ' default.conf     
sed -i -E '9 s/[[:space:]]*/    ssl_certificate_key \/etc\/ssl\/private\/domain.key;/' default.conf  
sed -i -E '9 a\ ' default.conf    
sed -i -E '10 s/[[:space:]]*/    ssl_session_cache shared:SSL:10m;/' default.conf
sed -i -E '10 a\ ' default.conf    
sed -i -E '11 s/[[:space:]]*/    ssl_session_timeout 10m;/' default.conf   

systemctl restart nginx
