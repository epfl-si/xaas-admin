<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est MyNAS


   AUTEUR : Lucien Chaboudez
   DATE   : Septembre 2020

   Prérequis:
   

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>

class NameGeneratorMyNAS
{

    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

		RET : Instance de l'objet
	#>
    NameGeneratorMyNAS()
    {
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le chemin d'accès UNC à un dossier utilisateur

        IN  : $serverName       -> Nom du serveur (nom court)
        IN  : $username         -> Nom d'utilisateur

        RET : UNC
	#>
    [string] getUserUNCPath([string]$serverName, [string]$username)
    {
        return ("\\{0}.epfl.ch\data\{1}" -f $serverName, $username)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le numéro du serveur pour un utilisateur

        IN  : $sciper   -> No sciper de l'utilisateur

        RET : No du serveur
	#>
    [int] getServerNo([string]$sciper)
    {
        return $sciper.Substring($sciper.length -1)
    }


}