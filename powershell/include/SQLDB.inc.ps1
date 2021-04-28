<#
   BUT : Classe permettant de faire des requêtes dans une DB MySQL. Beaucoup de choses déjà existantes
         trouvées sur le NET pour faire ceci, y compris le connecteur .NET fournis par MySQL
         (https://dev.mysql.com/downloads/connector/net/8.0.html) ne fonctionnent pas si le serveur ne fait pas de SSL.
         Le seul qui fonctionne, c'est le module SimplySQL !


   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2018

   Prérequis:
   Cette classe a besoin du module https://www.powershellgallery.com/packages/SimplySql/


   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base
   0.2 - On n'utilise plus "mysql.exe" car il posait problème depuis les machines dans le subnet 10.x.x.x
   0.3 - Extension pour supporter MSSQL

#>
# Importation du module pour faire le boulot
Import-Module SimplySQL

enum DBType 
{
    MySQL
    MSSQL
}

class SQLDB
{
    hidden [string]$connectionName

    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $dbType           -> Type de base de données, MSSQL ou MySQL
        IN  : $server           -> adresse IP ou nom IP du serveur
        IN  : $db               -> Nom de la base de données à laquelle se connecter
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
        IN  : $port             -> No de port à utiliser. Sera ignoré pour une DB MSSQL donc on peut passer $null
        IN  : $mysqlUseSSL      -> Dans le cas de MySQL, on doit dire si on veut faire du SSL ou pas

		RET : Instance de l'objet
	#>
    SQLDB([DBType]$dbType, [string]$server, [string]$db, [string]$username, [string]$password, [int]$port, [bool]$mysqlUseSSL)
    {
        # Définition d'un nom de connexion pour pouvoir l'identifier et la fermer correctement dans le cas
        # où on aurait plusieurs instances de l'objet en même temps.
        $this.connectionName = "SQLDB{0}" -f (Get-Random)

        # En fonction du type de DB
        switch($dbType)
        {
            MySQL
            {
                # On passe par une "connectionString" et non pas par la liste des arguments comme pour la partie MSSQL car
                # pour certaines requêtes avec MySQL, on a des dates et il faut ajouter "Allow Zero Datetime = True" pour
                # que ça fonctionne, et une connection string est le seul moyen de faire ça.
                $connectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};Allow Zero Datetime = True;" -f `
                                     $server, $port, $db, $username, $password
                if(!$mysqlUseSSL)
                {
                    $connectionString = "{0}SslMode=None;" -f $connectionString
                }
                Open-MySQLConnection -connectionString $connectionString -ConnectionName $this.connectionName
            }

            MSSQL
            {
                # Sécurisation du mot de passe et du nom d'utilisateur
                $credSecurePwd = $password | ConvertTo-SecureString -AsPlainText -Force
                $credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $credSecurePwd	
                
                Open-SqlConnection -Server $server -Database $db -Credential $credObject -ConnectionName $this.connectionName 
            }
        }
    }

    
    <#
		-------------------------------------------------------------------------------------
		BUT : Ferme la connexion
	#>
    [void]disconnect()
    {
        Close-SQLConnection -ConnectionName $this.connectionName
    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Exécute la requête MySQL passée en paramètre et retourne le résultat.

		IN  : $query    -> Requêtes MySQL à exécuter

        RET : Si SELECT => Résultat sous la forme d'un tableau associatif (IDictionnary)
              Si INSERT, UPDATE ou DELETE => Nombre d'éléments impactés
              Si une erreur survient, une exception est levée
	#>
    [PSCustomObject] execute([string]$query)
    {

        if($query.Trim() -eq "")
        {
            Throw "Empty query provided"
        }

        # Si on a demandé à récupérer des données, 
        if($query -like "SELECT*" )
        {
            # Exécution de la requête
            $queryResult = Invoke-SQLQuery -Query $query -ConnectionName $this.connectionName -AsDataTable

            $result = @()
            # On met en forme dans un tableau
            $queryResult.rows | ForEach-Object {
                $row = @{}
                For($i=0 ; $i -lt $queryResult.columns.count; $i++)
                {
#                    $row[$queryResult.columns[$i].ToString()] = $_[$i]
                    $row.add($queryResult.columns[$i].columnName, $_[$i])
                }
                $result += $row
            }

        }
        else # C'est une requête de modification 
        {
            $result = Invoke-SQLUpdate -Query $query -ConnectionName $this.connectionName
        }

        return $result

    }
}