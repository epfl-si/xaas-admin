<#
   BUT : Classe permettant de faire des requêtes dans une DB MySQL. Toutes les choses déjà existantes
         trouvées sur le NET pour faire ceci, y compris le connecteur .NET fournis par MySQL
         (https://dev.mysql.com/downloads/connector/net/8.0.html) ne fonctionnent pas si le serveur ne fait pas de SSL.
         Donc cette classe utilise simplement l'utilitaire "mysql.exe" qui est notamment fourni avec MySQL Workbench
         (https://www.mysql.com/fr/products/workbench/)

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2018

   Prérequis:
   Cette classe a besoin de l'utilitaire "mysql.exe" pour bien fonctionner. Celui-ci est installé en même temps que
   l'application MySQL Workbench (https://www.mysql.com/fr/products/workbench/) donc on peut par exemple utilise ceci
   pour l'avoir.


   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class MySQL
{
    hidden [string]$server
    hidden [string]$db
    hidden [string]$username
    hidden [string]$password

    hidden [System.Diagnostics.ProcessStartInfo]$processStartInfo

    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $server           -> adresse IP ou nom IP du serveur MySQL
        IN  : $db               -> Nom de la base de données à laquelle se connecter
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
        IN  : $pathToMySQLExe   -> Chemin jusqu'au programme 'mysql.exe' sur le disque dur

		RET : Instance de l'objet
	#>
    MySQL([string]$server, [string]$db, [string]$username, [string]$password, [string]$pathToMySQLExe)
    {
        $this.server    = $server
        $this.db        = $db
        $this.username  = $username
        $this.password  = $password

        # Check de la validité du chemin passé
        if( !(Test-Path $pathToMySQLExe))
        {
            Write-Error -Message ("Incorrect path to 'mysql.exe'... ({0})" -f $pathToMySQLExe) -ErrorAction Stop
        }

        # Création du nécessaire pour exécuter la commande MySQL par la suite.
        $this.processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $this.processStartInfo.FileName = $pathToMySQLExe
        $this.processStartInfo.UseShellExecute = $false
        $this.processStartInfo.CreateNoWindow = $false
        $this.processStartInfo.RedirectStandardOutput = $true
    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Exécute la requête MySQL passée en paramètre et retourne le résultat.

		IN  : $query    -> Requêtes MySQL à exécuter

        RET : Résultat sous la forme d'un tableau associatif (IDictionnary)
              $false si une erreur survient.
	#>
    [PSCustomObject] execute([string]$query)
    {
        $this.processStartInfo.Arguments = ('--host={0} --port=3306 --user={1} {2} --password="{3}" --execute "{4}"' -f `
                                            $this.server, $this.username, $this.db, $this.password, $query)
        $MySQLProcess = [System.Diagnostics.Process]::Start($this.processStartInfo)

        if($MySQLProcess.ExitCode -gt 0)
        {
            return $false
        }

        return $MySQLProcess.StandardOutput.ReadToEnd() | ConvertFrom-Csv -Delimiter "`t"

    }
}