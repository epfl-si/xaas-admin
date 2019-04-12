<#
   BUT : Contient les informations sur MySQL.
         La configuration qui semble manquer ici peut être trouvée dans le fichier de configuration de
         Django dans le dossier parent de celui-ci, dans le fichier "secrets.json"

         Les informations contenues dans ce fichier sont utilisées pour compléter si besoin la 
         structure renvoyée par la fonction 'loadMySQLInfos'

   AUTEUR : Lucien Chaboudez
   DATE   : Juin 2018

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>

# Noms de la base de données à utiliser en fonction de l'environnement
$TARGET_ENV_MYSQL_DB_NAME = @{$global:TARGET_ENV__DEV = "xaas_admin_dev"
                                     $global:TARGET_ENV__TEST = "xaas_admin_test"
                                     $global:TARGET_ENV__PROD = "xaas_admin_prod"}

# Nom de l'utilisateur pour accéder à la base de données MySQL
$MYSQL_USERNAME = "xaas_admin_user"

# Chemin jusqu'au fichier "mysql.exe"
$global:MYSQL_CLIENT_EXE = "C:\Program Files\MySQL\MySQL Workbench 6.3 CE\mysql.exe"

# Nom des champs dans la table qui contient la liste des services
$global:MYSQL_ITS_SERVICES__SHORTNAME = 'its_serv_short_name'
$global:MYSQL_ITS_SERVICES__LONGNAME = 'its_serv_long_name'
$global:MYSQL_ITS_SERVICES__SNOWID = 'its_serv_snow_id'


<#
	-------------------------------------------------------------------------------------
	BUT : Charge les informations de connexion à la DB MySQL depuis le fichier passé
		  en paramètre (.env) qui est le même que celui utilisé pour l'application Django
	   
	IN  : $file			-> Chemin jusqu'au fichier à charger.
	IN  : $targetEnv	-> Nom de l'environnement "cible"
#>
function loadMySQLInfos
{
	param([string]$file, [string]$targetEnv)

	# Si le fichier n'existe pas
	if(-not( Test-Path $file))
	{
		Throw ("ENV file not found ({0})" -f $file)
	}

	# Chargement du code JSON
	$infos = @{}
	# Chargement du fichier .env et des déclarations contenues dans celui-ci (en virant les lignes vides ou commençant par #)
	((Get-Content -Path $file) -notlike "#*").Trim() -notlike "" | ForEach-Object { 
		$name = $_.Split("=")[0]
		$value = $_.Split("=")[1]
		$infos.$name = $value }

	# Si on n'a pas overridé le nom de la DB dans le fichier "secrets.json", on l'initialise avec le contenu de $global:TARGET_ENV_MYSQL_DB_NAME
	if(! $infos.ContainsKey('MYSQL_DATABASE'))
	{
		$infos.MYSQL_DATABASE = $TARGET_ENV_MYSQL_DB_NAME[$targetEnv]
	}
    
    # Si on n'a pas overridé le nom de le l'utilisateur dans le fichier "secrets.json", on l'initialise 
	if(! $infos.ContainsKey('MYSQL_USER'))
	{
		$infos.MYSQL_USER = $MYSQL_USERNAME
	}

	return $infos
}