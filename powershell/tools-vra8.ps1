<#
USAGES:
	tools-vra8.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action addCatalogProject -name <name> -privacy (private|public)
    tools-vra8.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delCatalogProject -name <name>
#>
<#
	BUT 		: Permet de faire différentes actions sur l'infra vRA

	DATE 		: Juin 2021
	AUTEUR 	: Lucien Chaboudez


	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>
param ( [string]$targetEnv, 
        [string]$targetTenant, 
        [string]$action, 
        [string]$name,
        [string]$privacy)


. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ResumeOnFail.inc.ps1"))


# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRA8API.inc.ps1"))



# Chargement des fichiers de configuration
$configVra 		= [ConfigReader]::New("config-vra8.json")
$configGlobal 	= [ConfigReader]::New("config-global.json")


# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_ADD_CATALOG_PROJECT    = "addCatalogProject"
$ACTION_DELETE_CATALOG_PROJECT = "delCatalogProject"



<#
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
									Programme principal
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
#>


# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$logPath = @('tools', ('vra8-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()))
$logHistory =[LogHistory]::new($logPath, $global:LOGS_FOLDER, 120)

# On contrôle le prototype d'appel du script
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

$logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))


# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

# Création d'une connexion au serveur vRA pour accéder à ses API REST
$logHistory.addLineAndDisplay("Connecting to vRA...")
$vra = [vRA8API]::new($configVra.getConfigValue(@($targetEnv, "infra",  $targetTenant, "server")),
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))


switch($action)
{
    # -- Nouveau catalogue de projet
    $ACTION_ADD_CATALOG_PROJECT
    {
        $logHistory.addLineAndDisplay(("Searching if Catalog Project '{0}' already exists..." -f $name))
        $catalogProject = $vra.getProject($name)

        # Si le projet existe déjà
        if($null -ne $catalogProject)
        {
            $logHistory.addWarningAndDisplay(("Catalog Project '{0}' already exists" -f $name))
        }
        else # Le projet n'existe pas encore
        {   
            # -- GitHub ou GitLab
            # Chemin dans GitHub
            $gitPath = $nameGenerator.getGitHubCatalogPath($name)
            
            $gitHubIntegrationId = $configVra.getConfigValue(@($targetEnv, "git", "integrationId"))
            $gitRepo = $configVra.getConfigValue(@($targetEnv, "git", "repository"))
            $gitBranch = $configVra.getConfigValue(@($targetEnv, "git", "branch"))

            Write-Host ("-> Please add a folder '{0}' (with an empty README file) on '{1}' branch on GitHub repository '{2}'. " -f $gitPath, $gitBranch, $gitRepo) -ForegroundColor:Blue -NoNewLine
            Read-Host -Prompt "Then, hit ENTER to continue"

            $catalogPrivacy = [CatalogProjectPrivacy]$privacy

            $description = $nameGenerator.getCatalogProjectDescription($name, $catalogPrivacy)

            # Définition du type de projet
            $projectType = switch($catalogPrivacy)
            {
                Public { [ProjectType]::PublicCatalog }
                Private { [ProjectType]::PrivateCatalog }
            }

            $customProperties = @{
                $global:VRA_CUSTOM_PROP_VRA_PROJECT_TYPE = $projectType.toString()
            }

            $logHistory.addLineAndDisplay(("Adding project '{0}'..." -f $name))
            $catalogProject = $vra.addProject($name, $description, "", $customProperties, $null, $null, $null)

            try
            {
                $logHistory.addLineAndDisplay(("Adding Git source for '{0}' project..." -f $name))
                $gitSource = $vra.addCatalogProjectGitHubSource($name, $catalogProject, $gitHubIntegrationId, [GitHubContentType]::CloudTemplates, $gitRepo, $gitPath, $gitBranch)
            }
            catch
            {
                $logHistory.addWarningAndDisplay("Error adding Git source, deleting added project")
                $vra.deleteProject($catalogProject)
                Throw
            }
            
            # Recherche du nom de la "Content Source"
			$contentSourceName = $nameGenerator.getCatalogProjectContentSourceName($name)

            $logHistory.addLineAndDisplay(("Creating Content Source '{0}'..." -f $contentSourceName))
			$contentSource = $vra.addContentSources($contentSourceName, $catalogProject)
			
        }
        
    }


    # -- Suppression d'un catalogue de projet
    $ACTION_DELETE_CATALOG_PROJECT
    {
        # Recherche du nom de la "Content Source"
        $contentSourceName = $nameGenerator.getCatalogProjectContentSourceName($name)

        $logHistory.addLineAndDisplay(("Getting Content Source '{0}'..." -f $contentSourceName))
        $contentSource = $vra.getContentSource($contentSourceName)
        # Si pas trouvé
        if($null -eq $contentSource)
        {
            $logHistory.addLineAndDisplay(("-> Content Source '{0}' doesn't exists" -f $contentSourceName))
        }
        else
        {
            $logHistory.addLineAndDisplay(("-> Deleting Content Source '{0}'..." -f $contentSourceName))
            $vra.deleteContentSource($contentSource)
        }
        
        $logHistory.addLineAndDisplay(("Getting Git source '{0}'..." -f $name))

        $gitSource = $vra.getCatalogProjectGitHubSource($name)

        if($null -eq $gitSource)
        {
            $logHistory.addLineAndDisplay(("-> Git source '{0}' doesn't exists" -f $name))
        }
        else
        {
            $logHistory.addLineAndDisplay(("-> Git source '{0}', deleting it..." -f $name))
            $vra.deleteCatalogProjectGitHubSource($gitSource)
        }

        $logHistory.addLineAndDisplay(("Getting Catalog Project '{0}'..." -f $name))

        $catalogProject = $vra.getProject($name)

        # Si déjà effacé
        if($null -eq $catalogProject)
        {
            $logHistory.addLineAndDisplay(("-> Catalog Project '{0}' doesn't exists..." -f $name))
        }
        else
        {
            
            $logHistory.addLineAndDisplay(("-> Catalog Project '{0}' exists, deleting it..." -f $name))
            $vra.deleteProject($catalogProject)
        }
        
    }


    default: {
        Throw "Action not supported"
    }
}