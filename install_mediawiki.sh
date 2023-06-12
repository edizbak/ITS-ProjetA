
#!/bin/bash

# Mise en place fichier de logs
LOGS_FILE="/tmp/install_mediawiki.log"
echo -e "You will find vagrant provisionings logs below"  > ${LOGS_FILE}

# Mise à jour systèmes pour avoir des paquets frais
apt-get -y update >> ${LOGS_FILE}
apt-get -y upgrade >> ${LOGS_FILE}

echo "installation des logiciels à mettre en place sur Mediawiki 1 et 2"
if [ $1 == "node1" -o $1 == "node2" ]
then
  # Installation Mediawiki
  apt-get -y install mediawiki at | tee -a ${LOGS_FILE}  
  # apt-get install rsync at
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
  sed -ie "/bind-add/s/^/# /" /etc/mysql/mariadb.conf.d/50-server.cnf
  systemctl restart mariadb.service

  # Création clef d'échange avec mediawiki 2
  echo -e "Création clef d'échange avec mediawiki 2"
  mkdir /vagrant/tmp
  ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ""
  # Test code retour pour que le script attende l'exécution de ssh-keygen
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
  cat > /home/vagrant/db_bkup.sh <<EOF
#!/bin/bash
# Ce script sert à lancer la sauvegarde de la base de donnée, ce qui comprend
# l'export et la compression du fichier
BKUP_NAME=\$(date +"%Y_%m_%d_%I_%M_%p")
BKUP_DIR=/home/vagrant/bkups
sudo mysqldump -u wikiuser1 --password=wikipwd my_wiki > \
 \${BKUP_DIR}/backup_\$BKUP_NAME.sql
sleep 3
tar cvzf \${BKUP_DIR}/\$BKUP_NAME.tar.gz \${BKUP_DIR}/backup_\$BKUP_NAME.sql --remove-files
sleep 3
if [[ ! \$1 == run1 ]] ; then
  rsync -a \${BKUP_DIR}/ vagrant@192.168.99.32:\${BKUP_DIR}
fi
echo \$1
if [[ \$(ls \$BKUP_DIR | grep -c gz) -gt 15 ]] ; then
  cd \$BKUP_DIR || return
  rm "\$(ls -t | tail -1)"
fi

EOF

  # Job Cron de sauvegarde automatique à 2h00
  echo -e "Création job de sauvegarde automatique"
  chmod 740 /home/vagrant/db_bkup.sh
  mkdir /home/vagrant/bkups

  # Première exécution sauvegarde pour setup rsync
  if (/home/vagrant/db_bkup.sh  run1) ; then
    echo -e "Setup sauvegarde ok"
    chown vagrant:vagrant /home/vagrant/db_bkup.sh
    chown vagrant:vagrant /home/vagrant/bkups
    chown vagrant:vagrant /home/vagrant/bkups/*
  else
    echo -e "Echec setup sauvegarde, merci de contacter l'auteur"
  fi

  echo -e '0 3 * * * vagrant /home/vagrant/db_bkup.sh' > /etc/cron.d/dbbkup

  # Création script de restauration
  cat > /home/vagrant/db_restore.sh <<EOF
#!/bin/bash
# Ce script sert à lancer la restauration de la base de données
BKUP_DIR=/home/vagrant/bkups
echo -e "Récupération sauvegardes sur mediawiki 2"
rsync -aP vagrant@192.168.99.32:\${BKUP_DIR}/ \$BKUP_DIR
if [[ -z \$1 ]] ; then
 echo -e "Choisir la sauvegarde à restaurer :"
 ls \$BKUP_DIR | grep gz
 read saveFile
 tar xvzf \${BKUP_DIR}/\$saveFile -C / > bkup_file
else
 tar xvzf \${BKUP_DIR}/\$1 -C / > bkup_file
fi
while [[ ! \$? == 0 ]] ; do
  echo -e "Nom de fichier incorrect, merci de sélectionner un fichier dans la liste suivante :"
  ls \$BKUP_DIR | grep gz
  read saveFile
  tar xvzf \${BKUP_DIR}/\$saveFile -C / > bkup_file
done
Bkup_File="/\$(cat bkup_file)"
echo -e "Restauration en cours..."
sudo mysql -u root my_wiki < \$Bkup_File &2> /dev/null
if [[ ! \$? == 0 ]] ; then
 sudo mysql -e "CREATE DATABASE my_wiki;"
 sudo mysql -u root my_wiki < \$Bkup_File &2> /dev/null
 if [[ ! \$? == 0 ]] ; then
  echo -e "Echec restauration, merci de contacter l'auteur"
  exit 1
 fi
fi

EOF

  chmod 740 /home/vagrant/db_restore.sh
  chown vagrant:vagrant /home/vagrant/db_restore.sh

fi

if [ $1 == "node2" ]
then
  # Lancement du script d'install de mediawiki2
  echo -e "Configuration de l'application Mediawiki 2"
  php /usr/share/mediawiki/maintenance/install.php --dbname=my_wiki --dbserver="192.168.99.31" \
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

  # Copie clef 2
  echo -e "Mise en place clef 2"
  mv /vagrant/tmp/id2 /home/vagrant/.ssh/id_rsa && mv /vagrant/tmp/id2.pub /home/vagrant/.ssh/id_rsa.pub
  if [[ -e /home/vagrant/.ssh/id_rsa && -e /home/vagrant/.ssh/id_rsa.pub ]] ; then
    rm -r /vagrant/tmp
  fi
  chown vagrant:vagrant /home/vagrant/.ssh/*
  chmod 600 /home/vagrant/.ssh/*

  # Mise en place dossier sauvegarde
  mkdir /home/vagrant/bkups
  chown vagrant:vagrant /home/vagrant/bkups


fi


if [ $1 == "node2" ]
then
 LVMLOGS_FILE="/tmp/mise_en_place_lvm.log"
 echo -e "You will find LVM provisionings logs below"  > ${LVMLOGS_FILE}
 #Mise en place d'une solution de stockage LVM:
 #Vérification de la présence des disques durs
 echo "Vérification de la présence des disques durs." >> ${LVMLOGS_FILE}
 lsblk >> ${LVMLOGS_FILE}

 # Installation du package LVM
 echo "Installation du package LVM." >> ${LVMLOGS_FILE}
 apt-get -y install lvm2
 echo $? >> ${LVMLOGS_FILE}

 # On déclare le(s) disque(s) dur(s) virtuel(s) en Volume Physique LVM (PV = Physical Volume)
 echo "On déclare le(s) disque(s) dur(s) virtuel(s) en Volume Physique LVM." >> ${LVMLOGS_FILE}
 pvcreate /dev/sdb
 echo $? >> ${LVMLOGS_FILE}

 # Visualisation des PV
 echo "Visualisation des PV." >> ${LVMLOGS_FILE}
 lvmdiskscan >> ${LVMLOGS_FILE}
 pvdisplay >> ${LVMLOGS_FILE}

 # Création d’un VG (Volume Group)
 echo "Création d’un VG." >> ${LVMLOGS_FILE}
 vgcreate vg1 /dev/sdb
 echo $? >> ${LVMLOGS_FILE}

 # Visualisation des VG
 echo "Visualisation des VG." >> ${LVMLOGS_FILE}
 vgdisplay --units=G >> ${LVMLOGS_FILE}
 vgs >> ${LVMLOGS_FILE}

 # Création des LV (Logical Volume), option -n pour le nom
 echo "Création de LV part1." >> ${LVMLOGS_FILE}
 lvcreate -l 50%VG -n part1 vg1
 echo $? >> ${LVMLOGS_FILE}
 echo "Création de LV part2." >> ${LVMLOGS_FILE}
 lvcreate -L 1G -n part2 vg1
 echo $? >> ${LVMLOGS_FILE}

 # Visualisation des LV
 echo "Visualisation des LV." >> ${LVMLOGS_FILE}
 lvscan >> ${LVMLOGS_FILE}
 lvdisplay >> ${LVMLOGS_FILE}

 #  Formatage en EXT4, option -t pour le type de système de fichiers
 echo "Formatage en EXT4 de part1." >> ${LVMLOGS_FILE}
 mkfs -t ext4 /dev/vg1/part1
 echo $? >> ${LVMLOGS_FILE}
 echo "Formatage en EXT4 de part2." >> ${LVMLOGS_FILE}
 mkfs -t ext4 /dev/vg1/part2
 echo $? >> ${LVMLOGS_FILE}

 # Création des points de montage
 echo "Création du point de montage de part1." >> ${LVMLOGS_FILE}
 mkdir /my_lvm_volume1
 echo $? >> ${LVMLOGS_FILE}
 echo "Création du point de montage de part2." >> ${LVMLOGS_FILE}
 mkdir /my_lvm_volume2
 echo $? >> ${LVMLOGS_FILE}

 # Montage du système de fichiers, sur les points de montage
 echo "Montage du système de fichiers, sur le point de montage de my_lvm_volume1." >> ${LVMLOGS_FILE}
 mount /dev/vg1/part1 /my_lvm_volume1
 echo $? >> ${LVMLOGS_FILE}
 echo "Montage du système de fichiers, sur le point de montage de my_lvm_volume2." >> ${LVMLOGS_FILE}
 mount /dev/vg1/part2 /my_lvm_volume2
 echo $? >> ${LVMLOGS_FILE}

 # Modification du fichier /etc/fstab pour activer le montage automatique des partitions au démarrage du système d'exploitation
 echo "Modification du fichier /etc/fstab pour activer le montage automatique des partitions au démarrage du système d'exploitation" >> ${LVMLOGS_FILE}
 file="/etc/fstab"
 echo $? >> ${LVMLOGS_FILE}

 echo "Copie du morceau de ligne du fichier /etc/fstab depuis <ext4> et jusqu'à la fin de la même ligne." >> ${LVMLOGS_FILE}
 text=$(sed -n 's/.*\(ext4[[:space:]]*.*\)$/\1/p' $file)
 echo $? >> ${LVMLOGS_FILE}

 echo "Les nouvelles lignes qu'on doit ajouter." >> ${LVMLOGS_FILE}
 line1="/dev/vg1/part1 /my_lvm_volume1 $text"
 line2="/dev/vg1/part2 /my_lvm_volume2 $text"
 echo $? >> ${LVMLOGS_FILE}

 echo "Les nouvelles lignes sont mises dans le fichier /etc/fstab, après la ligne que commence par UUID." >> ${LVMLOGS_FILE}
 sed -i "/^UUID/ a\\$line1\n$line2" $file
 echo $? >> ${LVMLOGS_FILE}

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
