#!/bin/bash

# BUT : Met en place la configuration de mail personnalisés sur un environnement donné (prod, test, dev).
#       Tous les serveurs d'un environnement donné sont traités l'un après l'autre, avec un possible délai entre 
#       chacun, histoire de laisser le temps aux services de redémarrer.
#
#       Le script se charge de :
#       - Créer des fichiers ZIP avec les différentes ressources à mettre sur les serveurs
#       - Faire un backup (archive) des fichiers existants sur le serveur
#       - Copier les fichiers ZIP sur les serveurs et les extraires.
#       - Redémarrer les services sur les serveurs pour prendre les modifications en compte.

# REMARQUE: Pour fonctionner, ce script a besoin que la clef SSH publique de l'utilisateur qui l'exécutera soit
#           présente sur les serveurs cibles (voir fichier deloy.config pour avoir la liste des serveurs)


SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
CONFIG_FILE="${SCRIPT_PATH}/../deploy.config"

# Si le fichier de config n'existe pas
if [ ! -e ${CONFIG_FILE} ]
then
    echo "Config file not found (${CONFIG_FILE}). Please create it from sample file"
    exit 1
fi
# Inclusion de la configuration
. ${CONFIG_FILE}
# Inclusion des fonctions 
. "${SCRIPT_PATH}/../functions.sh"

# Check des paramètres
if [ "$1" == "" ]
then
    echo "Missing targetEnv parameter"
    echo ""
    echo "Usage: $0 <targetEnv>"
    echo "   <targetEnv>: dev|test|prod"
    echo ""
    exit 1
fi

# Génération du nom de la variable dans laquelle il faudra aller chercher la liste des serveurs
SERVER_LIST_VAR="SERVER_LIST_"${1^^}
SERVER_MAIN_VAR="SERVER_MAIN_"${1^^}


RESOURCE_ZIP="bundle.zip"
RESOURCE_TARGET_DIR="/usr/lib/vcac/server/webapps/ROOT/"
RESOURCE_FOLDER_TO_UPDATE="bundle"

OLD_DIR="$(pwd)"


# ---------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------

# Contrôle de l'intialisation des variables de configuration
checkConfigVar $SERVER_LIST_VAR
checkConfigVar $SERVER_MAIN_VAR


cd ${SCRIPT_PATH}

# ---------------------------------------------------------------------------------
echo -n "Creating ZIP file... "
createZip ${RESOURCE_ZIP} ${RESOURCE_FOLDER_TO_UPDATE}

echo "done"

# ---------------------------------------------------------------------------------


# Parcours des appliances à mettre à jour
for vra in ${!SERVER_LIST_VAR}
do
    echo "Deploying on ${vra}..."
    
    echo -n "> Backuping 'index.jsp' if not already done... "
    # Sauvegarde du fichier 'index.jsp' si on ne l'a encore jamais backupé
    INDEX_JSP_FILE="${RESOURCE_TARGET_DIR}/index.jsp"
    ssh  -o "StrictHostKeyChecking=no" -q root@${vra} "if [ ! -e ${INDEX_JSP_FILE}.bak ]; then cp ${INDEX_JSP_FILE} ${INDEX_JSP_FILE}.bak; fi"
    echo "done"

    echo -n "> Copying ZIP file... "
    scp -q ${RESOURCE_ZIP} root@${vra}:${RESOURCE_TARGET_DIR}${RESOURCE_ZIP}
    echo "done"

    echo -n "> Updating files... "
    # On extrait les fichiers au bon endroit mais ils seront dans le dossier "bundle" donc il faut les déplacer dans le dossier parent
    # et ensuite supprimer le dossier "bundle"
    ssh -q root@${vra} "cd ${RESOURCE_TARGET_DIR}; unzip -q -ou ${RESOURCE_ZIP}; mv ${RESOURCE_FOLDER_TO_UPDATE}/images/* ./images/ ; rm -r ${RESOURCE_FOLDER_TO_UPDATE}"
    echo "done"

    echo -n "> Updating rights... "
    ssh -q root@${vra} "cd ${RESOURCE_TARGET_DIR}; chmod 755 images; chmod 555 iaas.css index.jsp images/*"
    echo "done"

    echo -n "> Cleaning... "
    ssh -q root@${vra} "rm ${RESOURCE_TARGET_DIR}${RESOURCE_ZIP};"
    echo "done"

done

echo -n "Local cleaning... "
rm ${RESOURCE_ZIP}
echo "done"

cd ${OLD_DIR}
