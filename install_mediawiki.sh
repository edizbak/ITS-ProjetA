
#!/bin/bash

# Mise en place fichier de logs
LOGS_FILE="/tmp/install_mediawiki.log"
echo -e "You will find vagrant provisionings logs below"  > ${LOGS_FILE}

# Mise à jour systèmes pour avoir des paquets frais
sudo apt-get -y update >> ${LOGS_FILE}
sudo apt-get -y upgrade >> ${LOGS_FILE}

echo "installation des logiciels à mettre en place sur Mediawiki 1 et 2"
if [ $1 == "node1" -o $1 == "node2" ]
then
  # Installation Mediawiki
  sudo apt-get -y install mediawiki | tee ${LOGS_FILE}  
  # echo -e "installation mediawiki ignorée pour tests"
fi

if [ $1 == "node1" ]
then
  # Création table my_wiki et utilisateurs wikiuser1 et wikiuser2
  echo -e "Création table et utilisateurs pour Mediawiki 1 et 2"
  sudo mysql -e "CREATE DATABASE my_wiki;"
  sudo mysql -e "CREATE USER 'wikiuser1'@'localhost' IDENTIFIED BY 'wikipwd';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON my_wiki.* TO 'wikiuser1'@'localhost' WITH GRANT OPTION;"
  sudo mysql -e "CREATE USER 'wikiuser2'@'192.168.99.32' IDENTIFIED BY 'wikipwd';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON my_wiki.* TO 'wikiuser2'@'192.168.99.32' WITH GRANT OPTION;"

  # Lancement du script d'install de mediawiki1
  echo -e "Configuration de l'application Mediawiki 1"
  sudo php /usr/share/mediawiki/maintenance/install.php --dbname=my_wiki --dbserver="localhost" \
  --server=http://192.168.99.31 --installdbuser=wikiuser1 --installdbpass=wikipwd \
  --dbuser=wikiuser1 --dbpass=wikipwd --scriptpath=/mediawiki --lang=en --pass=wiki_passwd \
  "Wiki Test" "Admin"

  # Mise en commentaire de la ligne 'bind-address' dans mariadb.conf pour permettre accès mediawiki2
  echo -e "Modification de la configuration de MariaDB pour permettre l'accès à Mediawiki 2"
  # tentative éjection sudo vu qu'on doit être  en root
  # sudo sed -ie "/bind-add/s/^/# /" /etc/mysql/mariadb.conf.d/50-server.cnf
  sed -ie "/bind-add/s/^/# /" /etc/mysql/mariadb.conf.d/50-server.cnf
  # sudo systemctl restart mariadb.service
  systemctl restart mariadb.service

  # Création clef d'échange avec mediawiki 2
  echo -e "Création clef d'échange avec mediawiki 2"
  mkdir /vagrant/tmp
  ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ""
  if [ $? == 0 ]
  then
    echo -e "génération ok, copie clef"
    cp ~/.ssh/id_rsa.pub /vagrant/tmp/id1
    mkdir /home/vagrant/.ssh
    cp ~/.ssh/id_rsa.pub /home/vagrant/.ssh && cp ~/.ssh/id_rsa /home/vagrant/.ssh
  fi

  echo -e "Création deuxième clef"
  ssh-keygen -t rsa -f ~/.ssh/id_rsa2 -N ""
  if [ $? == 0 ] ; then
    echo -e "génération ok, copie clef"
    mv ~/.ssh/id_rsa2 /vagrant/tmp/id2 && mv ~/.ssh/id_rsa2.pub /vagrant/tmp/id2.pub
    cat /vagrant/tmp/id2.pub >> /home/vagrant/.ssh/authorized_keys
  fi

  chown vagrant:vagrant /home/vagrant/.ssh/*
  chmod 600 /home/vagrant/.ssh/*

  # Installation outils de sauvegarde
  # apt-get
  
  # Création script de sauvegarde
  cat > /root/db_bkup.sh <<EOF
  #!/bin/bash
  # Ce script sert à lancer la sauvegarde de la base de donnée, ce qui comprend
  # l'export des données, la compression du fichier et son envoi sur mediawiki2
  BKUP_NAME=$(date +"%Y_%m_%d_%I_%M_%p")
  mysqldump -u wikiuser1 --password=wikipwd my_wiki > \
   /home/vagrant/bkups/backup_$BKUP_NAME.sql
  tar cvzf /home/vagrant/bkups/$BKUP_NAME.tar.gz /home/vagrant/bkups/backup_$BKUP_NAME.sql

  

EOF

  # Job Cron de sauvegarde automatique à 2h00
  echo -e "Création job de sauvegarde automatique"
  mkdir /home/vagrant/bkups
  echo -e '0 2 * * * mysqldump -u wikiuser1 --password=wikipwd my_wiki > \
  /home/vagrant/bkups/backup_$(date +"%Y_%m_%d_%I_%M_%p").sql' > /etc/cron.d/dbbkup
fi

if [ $1 == "node2" ]
then
  # Lancement du script d'install de mediawiki2
  echo -e "Configuration de l'application Mediawiki 2"
  sudo php /usr/share/mediawiki/maintenance/install.php --dbname=my_wiki --dbserver="192.168.99.31" \
  --server=http://192.168.99.32 --installdbuser=wikiuser2 --installdbpass=wikipwd \
  --dbuser=wikiuser2 --dbpass=wikipwd --scriptpath=/mediawiki --lang=en --pass=wiki_passwd \
  "Wiki Test" "Admin"

  # Récupération clef d'échange mediawiki1
  echo -e "Récupération clef d'échange mediawiki 1"
  mkdir /home/vagrant/.ssh
  cat /vagrant/tmp/id1 >> /home/vagrant/.ssh/authorized_keys &2> /dev/null
  if [ ! $? == 0 ]
  then
    echo -e "Erreur lors de la récupération de la clef d'échange mediawiki 1,"
    echo -e "contacter votre administrateur ou lire la documentation"
  else
    rm /vagrant/tmp/id1
  fi

  echo -e "Mise en place clef 2"
  mv /vagrant/tmp/id2 /home/vagrant/.ssh/id_rsa && mv /vagrant/tmp/id2.pub /home/vagrant/.ssh/id_rsa.pub
  chown vagrant:vagrant /home/vagrant/.ssh/*
  chmod 600 /home/vagrant/.ssh/*

  # ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ""

fi

if [ $1 == "master" ]
then
  echo "installation des logiciels à mettre en place sur Nginx"

 
  # Install zsh if needed
if [[ !(-z "$ENABLE_ZSH")  &&  ($ENABLE_ZSH == "true") ]]
    then
      echo "We are going to install zsh"
      sudo yum -y install zsh git
      echo "vagrant" | chsh -s /bin/zsh vagrant
      su - vagrant  -c  'echo "Y" | sh -c "$(curl -fsSL \
      https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
      su - vagrant  -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
      ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
      sed -i 's/^plugins=/#&/' /home/vagrant/.zshrc
      echo "plugins=(git  colored-man-pages aliases copyfile  copypath zsh-syntax-highlighting \
      jsontools)" >> /home/vagrant/.zshrc
      sed -i "s/^ZSH_THEME=.*/ZSH_THEME='agnoster'/g"  /home/vagrant/.zshrc
    else
      echo "The zsh is not installed on this server"
  fi

fi
echo "For this Stack, you will use $(ip -f inet addr show eth1 \
  | sed -En -e 's/.*inet ([0-9.]+).*/\1/p') IP Address"