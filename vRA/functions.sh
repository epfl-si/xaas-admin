#!/bin/bash

# BUT : Contient des fonctions utilisées par les scripts de déploiement

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