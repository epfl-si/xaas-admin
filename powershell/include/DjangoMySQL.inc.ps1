<#
   BUT : Classe permettant de communiquer avec l'application Django et plus particulièrement la DB de celui-ci.
         

   AUTEUR : Lucien Chaboudez
   DATE   : Juin 2018

   Prérequis:
   Les fichiers suivants doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - MySQL.inc.ps1
   - define.inc.ps1
   - define-mysql.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class DjangoMySQL
{
    hidden [MySQL] $mysql
    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $dbHost       -> Nom du serveur de la DB Django
        IN  : $dbPort       -> Port à utiliser pour l'accès à la DB
        IN  : $dbUser       -> Nom d'utilisateur
        IN  : $dbPass       -> Mot de passe
        IN  : $dbName       -> Nom de la DB

		RET : Instance de l'objet
	#>
    DjangoMySQL([string]$dbHost, [int]$dbPort, [string]$dbName, [string]$dbUser, [string]$dbPass)
    {
        $this.mysql = [MySQL]::new($dbHost, $dbName, $dbUser, $dbPass, $global:MYSQL_CLIENT_EXE, $dbPort)

    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Services
    #>
    [psobject]getServicesList()
    {
        $request = "SELECT * FROM its_services"

        return $this.mysql.execute($request)
    }

}