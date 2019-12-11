#!/bin/bash

# REMARQUE: Pour fonctionner, ce script a besoin que la clef SSH publique de l'utilisateur qui l'exécutera soit
#           présente sur les serveurs cibles (voir fichier deloy.config pour avoir la liste des serveurs)

SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
CONFIG_FILE="${SCRIPT_PATH}/deploy.config"

# Si le fichier de config n'existe pas
if [ ! -e ${CONFIG_FILE} ]
then
    echo "Config file not found (${CONFIG_FILE}). Please create it from sample file"
    exit 1
fi
# Inclusion de la configuration
. ${CONFIG_FILE}

# Check des paramètres
if [ "$1" == "" ]
then
    echo "Missing targetEnv parameter"
    echo ""
    echo "Usage: $0 <targetEnv>"
    echo "   <targetEnv>: dev|test|prod [<sleepMinBetweenServers>]"
    echo ""
    exit 1
fi

# Si on doit faire un "sleep" entre les serveurs
if [ "$2" == "" ]
then
    # Aucune pause, on trace !
    sleepSecBetween=0
else
    # Définition du nombre de secondes à attendre en fonction du nombre de minutes
    let sleepSecBetween=$2*60
fi

# Génération du nom de la variable dans laquelle il faudra aller chercher la liste des serveurs
SERVER_LIST_VAR="SERVER_LIST_"${1^^}
SERVER_MAIN_VAR="SERVER_MAIN_"${1^^}


RESOURCE_IMAGES_ZIP="images-email.zip"
RESOURCE_IMAGES_TARGET_DIR="/usr/lib/vcac/server/webapps/ROOT/"
RESOURCE_IMAGES_FOLDER_TO_UPDATE="images-email"

RESOURCE_EMAIL_ZIP="email.zip"
RESOURCE_EMAIL_TARGET_DIR="/vcac/templates/"
RESOURCE_EMAIL_FOLDER_TO_UPDATE="email"

OLD_DIR="$(pwd)"


# ---------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------

# Affiche un . par seconde durant le temps donné (en secondes) 
#
# $1    -> temps à attendre, en secondes
# $2    -> texte à afficher
function waitABit()
{
    local i=0

    # Si on ne doit en fait pas attendre...
    if [ $1 -eq 0 ]
    then
        return
    fi

    echo -n "$2 "

    while [ $i -lt $1 ]
    do
        sleep 1
        echo -n "."
        let i=i+1
    done
    echo ""
}

# ---------------------------------------------------------------------------------

# Crée un fichier ZIP mais efface celui-ci au préalable s'il existe déjà
#
# $1 -> Nom du fichier ZIP
# $2 -> Nom du dossier à ZIP pour créer le fichier
function createZip()
{
    local zipFile=$1
    local folderToZip=$2

    # Suppression du fichier s'il existe
    if [ -e ${zipFile} ]
    then
        rm ${zipFile}
    fi

    zip -q -r ${zipFile} ${folderToZip}
}


# ---------------------------------------------------------------------------------

# Contrôle qu'une variable de configuration soit bien initialisée
#
# $1 -> Nom de la variable à contrôler
function checkConfigVar()
{
    local varName=$1
    
    # Si on n'a rien
    if [ "${!varName}" == "" ]
    then
        echo "Variable not assigned!"
        echo "Please edit config file to set a value for ${varName}"
        echo ""
        exit 1
    fi
}

# ---------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------

# Contrôle de l'intialisation des variables de configuration
checkConfigVar $SERVER_LIST_VAR
checkConfigVar $SERVER_MAIN_VAR


cd ${SCRIPT_PATH}

# ---------------------------------------------------------------------------------

STYLES_FILE="styles.vm"
echo -n "Updating release date in '${STYLES_FILE}' files... "
# On met à jour la date de release avec la date courante avant de déployer
sed -i -E "s/[0-9]{4,4}-[0-9]{2,2}-[0-9]{2,2}\s[0-9]{2,2}:[0-9]{2,2}:[0-9]{2,2}+/`date +"%Y-%m-%d %H:%M:%S"`/g" email/html/core/defaults/${STYLES_FILE}
echo "done"


# ---------------------------------------------------------------------------------
HEADER_FILE="header.vm"
echo -n "Updating ${HEADER_FILE} file content to set correct URL... "
# Recherche des fichiers pour les tenants
for h in `find email/html/core/tenants/ -name ${HEADER_FILE}`
do
    # Mise à jour du fichier courant avec le nom du host de l'environnement courant.
    sed -i -E "s/https:\/\/[^\/]+/https:\/\/${!SERVER_MAIN_VAR}/g" $h
done

echo "done"

# ---------------------------------------------------------------------------------
echo -n "Creating ZIP files... "
createZip ${RESOURCE_EMAIL_ZIP} ${RESOURCE_EMAIL_FOLDER_TO_UPDATE}
createZip ${RESOURCE_IMAGES_ZIP} ${RESOURCE_IMAGES_FOLDER_TO_UPDATE}

echo "done"

# ---------------------------------------------------------------------------------

previousServer=""

# Parcours des appliances à mettre à jour
for vra in ${!SERVER_LIST_VAR}
do
    # Si on n'est pas à la première exécution de la boucle
    if [ "${previousServer}" != "" ]
    then
        # On attend le nombre de seconde données (peut-être 0) avant de passer au serveur suivant
        waitABit $sleepSecBetween "Waiting ${sleepSecBetween} sec before next server"
    fi
    

    echo "Deploying on ${vra}..."

    echo "> Email templates"
    echo -n ">> Creating target folder if not exists... "
    # Création du dossier cible si n'existe pas.
    ssh  -o "StrictHostKeyChecking=no" -q root@${vra} "if [ ! -e ${RESOURCE_EMAIL_TARGET_DIR} ]; then mkdir -p ${RESOURCE_EMAIL_TARGET_DIR}; fi"
    echo "done"

    echo -n ">> Copying ZIP file... "
    scp -q ${RESOURCE_EMAIL_ZIP} root@${vra}:${RESOURCE_EMAIL_TARGET_DIR}${RESOURCE_EMAIL_ZIP}
    echo "done"

    echo -n ">> Creating backup... "
    ssh -q root@${vra} "cd ${RESOURCE_EMAIL_TARGET_DIR}; tar -cf ${RESOURCE_EMAIL_FOLDER_TO_UPDATE}-backup-`date '+%Y-%m-%d_%H-%M-%S'`.tar ${RESOURCE_EMAIL_FOLDER_TO_UPDATE}"
    echo "done"

    echo -n ">> Removing old files... "
    ssh -q root@${vra} "cd ${RESOURCE_EMAIL_TARGET_DIR}; rm -r ${RESOURCE_EMAIL_FOLDER_TO_UPDATE}"
    echo "done"

    echo -n ">> Updating files... "
    ssh -q root@${vra} "cd ${RESOURCE_EMAIL_TARGET_DIR}; unzip -q -o ${RESOURCE_EMAIL_ZIP}"
    echo "done"

    echo -n ">> Updating rights... "
    ssh -q root@${vra} "find /vcac -type d -exec chmod o+rx {} \;"
    ssh -q root@${vra} "find /vcac -type f -exec chmod o+r {} \;"
    echo "done"
    
    
    # Ressources des mails (images utilisées au sein de ceux-ci)

    echo "> Email resources"
    echo -n ">> Copying ZIP file... "
    scp -q ${RESOURCE_IMAGES_ZIP} root@${vra}:${RESOURCE_IMAGES_TARGET_DIR}${RESOURCE_IMAGES_ZIP}
    echo "done"

    echo -n ">> Removing old files... "
    ssh -q root@${vra} "cd ${RESOURCE_IMAGES_TARGET_DIR}; rm -r ${RESOURCE_IMAGES_FOLDER_TO_UPDATE}"
    echo "done"

    echo -n ">> Updating files... "
    ssh -q root@${vra} "cd ${RESOURCE_IMAGES_TARGET_DIR}; unzip -q -o ${RESOURCE_IMAGES_ZIP}"
    echo "done"


    echo -n "> Cleaning... "
    ssh -q root@${vra} "rm ${RESOURCE_EMAIL_TARGET_DIR}${RESOURCE_EMAIL_ZIP}; rm ${RESOURCE_IMAGES_TARGET_DIR}${RESOURCE_IMAGES_ZIP};"
    echo "done"

    echo "> Restarting service... "
    ssh -q root@${vra} "service vcac-server restart"
    
    # Mise à jour
    previousServer=${vra}
done

echo -n "Local cleaning... "
rm ${RESOURCE_EMAIL_ZIP}
rm ${RESOURCE_IMAGES_ZIP}
echo "done"

cd ${OLD_DIR}
echo ""
echo "All servers updated!"
waitABit 120 "Waiting for all services to restart"
echo ""
echo "You can now try to login on one of the servers"
echo ""
echo "Live long and prosper !"
echo << endOfMessage "
               .
              .:.
             .:::.
            .:::::.
        ***.:::::::.***
   *******.:::::::::.*******       
 ********.:::::::::::.********     
********.:::::::::::::.********    
*******.::::::'***'::::.*******    
******.::::'*********'::.******    
 ****.:::'*************':.****
   *.::'*****************'.*
   .:'  ***************    .
  . "
endOfMessage