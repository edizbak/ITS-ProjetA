
#!/bin/bash

LOGS_FILE="/tmp/install_mediawiki.log"
echo -e "You will find vagrant provisionings logs below"  > ${LOGS_FILE}

sudo apt-get -y update >> ${LOGS_FILE}
sudo apt-get -y upgrade >> ${LOGS_FILE}

echo "installation des logiciels à mettre en place sur Mediawiki 1 et 2"
if [ $1 == "node1" -o $1 == "node2" ]
then
  sudo apt-get -y install mediawiki | tee ${LOGS_FILE}  
fi

if [ $1 == "node1" ]
then
  echo -e "Création table et utilisateurs pour Mediawiki 1 et 2"
  sudo mysql -e "CREATE DATABASE my_wiki;"
  sudo mysql -e "CREATE USER 'wikiuser1'@'localhost' IDENTIFIED BY 'wikipwd';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON my_wiki.* TO 'wikiuser1'@'localhost' WITH GRANT OPTION;"
  sudo mysql -e "CREATE USER 'wikiuser2'@'192.168.99.32' IDENTIFIED BY 'wikipwd';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON my_wiki.* TO 'wikiuser2'@'192.168.99.32' WITH GRANT OPTION;"
  echo -e "Configuration de l'application Mediawiki 1"
  sudo php /usr/share/mediawiki/maintenance/install.php --dbname=my_wiki --dbserver="localhost" \
  --server=http://192.168.99.31 --installdbuser=wikiuser1 --installdbpass=wikipwd \
  --dbuser=wikiuser1 --dbpass=wikipwd --scriptpath=/mediawiki --lang=en --pass=wiki_passwd \
  "Wiki Test" "Admin"
  echo -e "Modification de la configuration de MariaDB pour permettre l'accès à Mediawiki 2"
  sudo sed -ie "/bind-add/s/^/# /" /etc/mysql/mariadb.conf.d/50-server.cnf
  sudo systemctl restart mariadb.service
  # sudo sed -i -e /\$wgServer/s/localhost\"/192\.168\.99\.31\"/p /etc/mediawiki/LocalSettings.php
fi

if [ $1 == "node2" ]
then
  echo -e "Configuration de l'application Mediawiki 2"
  sudo php /usr/share/mediawiki/maintenance/install.php --dbname=my_wiki --dbserver="192.168.99.31" \
  --server=http://192.168.99.32 --installdbuser=wikiuser2 --installdbpass=wikipwd \
  --dbuser=wikiuser2 --dbpass=wikipwd --scriptpath=/mediawiki --lang=en --pass=wiki_passwd \
  "Wiki Test" "Admin"
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
      su - vagrant  -c  'echo "Y" | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
      su - vagrant  -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
      sed -i 's/^plugins=/#&/' /home/vagrant/.zshrc
      echo "plugins=(git  colored-man-pages aliases copyfile  copypath zsh-syntax-highlighting jsontools)" >> /home/vagrant/.zshrc
      sed -i "s/^ZSH_THEME=.*/ZSH_THEME='agnoster'/g"  /home/vagrant/.zshrc
    else
      echo "The zsh is not installed on this server"
  fi

fi
echo "For this Stack, you will use $(ip -f inet addr show eth1 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p') IP Address"