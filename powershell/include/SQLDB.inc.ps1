<#
   BUT : Classe permettant de faire des requêtes dans une DB MySQL. Beaucoup de choses déjà existantes
         trouvées sur le NET pour faire ceci, y compris le connecteur .NET fournis par MySQL
         (https://dev.mysql.com/downloads/connector/net/8.0.html) ne fonctionnent pas si le serveur ne fait pas de SSL.
         Le seul qui fonctionne, c'est le module SimplySQL !


   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2018

   Prérequis:
   Cette classe a besoin du module https://www.powershellgallery.com/packages/SimplySql/


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
    hidden [LogHistory] $logHistory

    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $dbType           -> Type de base de données, MSSQL ou MySQL
        IN  : $server           -> adresse IP ou nom IP du serveur
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
        IN  : $port             -> No de port à utiliser. Sera ignoré pour une DB MSSQL donc on peut passer $null
        IN  : $mysqlUseSSL      -> Dans le cas de MySQL, on doit dire si on veut faire du SSL ou pas
        IN  : $db               -> (optionel) Nom de la base de données à laquelle se connecter

		RET : Instance de l'objet
    #>
    SQLDB([DBType]$dbType, [string]$server, [string]$username, [string]$password, [int]$port, [bool]$mysqlUseSSL)
    {
        # Vu qu'on a 2 constructeurs avec 2 listes de paramètres, on est obligé de passer par une fonction 
        # "externe" pour faire l'initialisation, on ne peut pas appeler un constructeur depuis un autre.
        # Solution trouvée ici: https://stackoverflow.com/questions/44413206/constructor-chaining-in-powershell-call-other-constructors-in-the-same-class
        $this.init($dbType, $server, $username, $password, $port, $mysqlUseSSL, "")
    }
    SQLDB([DBType]$dbType, [string]$server, [string]$username, [string]$password, [int]$port, [bool]$mysqlUseSSL, [string]$db)
    {
        $this.init($dbType, $server, $username, $password, $port, $mysqlUseSSL, $db)
    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Fonction qui fait office de constructeur de classe.

        IN  : $dbType           -> Type de base de données, MSSQL ou MySQL
        IN  : $server           -> adresse IP ou nom IP du serveur
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
        IN  : $port             -> No de port à utiliser. Sera ignoré pour une DB MSSQL donc on peut passer $null
        IN  : $mysqlUseSSL      -> Dans le cas de MySQL, on doit dire si on veut faire du SSL ou pas
        IN  : $db               -> Nom de la base de données à laquelle se connecter

		RET : Instance de l'objet
    #>
    hidden [void] init([DBType]$dbType, [string]$server, [string]$username, [string]$password, [int]$port, [bool]$mysqlUseSSL, [string]$db)
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
		BUT : Activation du logging "debug" des requêtes faites sur le système distant.

		IN  : $logHistory	-> Objet de la classe LogHistory qui va permettre de faire le logging.
	#>
	[void] activateDebug([LogHistory]$logHistory)
	{
		$this.logHistory = $logHistory
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une ligne au debug si celui-ci est activé

		IN  : $line	-> La ligne à ajouter
	#>
	[void] debugLog([string]$line)
	{
		if($null -ne $this.logHistory)
		{
			$funcName = ""

			ForEach($call in (Get-PSCallStack))
			{
				if(@("debugLog") -notcontains $call.FunctionName)
				{
					$funcName = $call.FunctionName
					break
				}
			}
			
			$this.logHistory.addDebug(("{0}::{1}(): {2}" -f $this.GetType().Name, $funcName, $line))
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
        $this.debugLog(("Executing SQL query:`n{0}" -f $query))

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

    [void] createDB([string]$dbName)
    {
        # TODO:
    }

    [void] deleteDB([string]$dbName)
    {
        # TODO:
    }
}