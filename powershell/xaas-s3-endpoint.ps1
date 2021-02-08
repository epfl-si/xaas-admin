<#
USAGES:
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action create -unitOrSvcID <unitOrSvcID> -friendlyName <friendlyName> [-linkedTo <linkedTo>] [-bucketTag <bucketTag>]
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action delete -bucketName <bucketName>
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action regenKeys -bucketName <bucketName> -userType (ro|rw|all)
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action versioning -bucketName <bucketName> -enabled (true|false)
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action versioning -bucketName <bucketName> -status
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action linkedBuckets -bucketName <bucketName>
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action getUsers -bucketName <bucketName>
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action bucketExists -bucketName <bucketName>
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action bucketIsEmpty -bucketName <bucketName>
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action getBuckets 
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research|backupadmins -action getBucketsUsage 
#>
<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet d'effectuer diverses
                  opérations en rapport avec le service Scality S3 en tant que XaaS.
                  Pour accéder à Scality, on utilise 2 manières de faire: 
                  - via le module Amazon PowerShell S3 pour les éléments qui y sont implémentés
                  - via l'API REST utilisée par la console Web Scality pour les CmdLets Amazon pas 
                    (encore) implémentés dans Scality

	DATE 	: Août 2019
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.02

    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.
    - Ce script prend du temps à s'exécuter car il charge le PowerCLI Amazon S3 et ce dernier étant énoOOOrme, 
        ça prend du temps... une tentative de ne  charger que les CmdLets nécessaires a été faite mais ça 
        n'accélère en rien...


    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    Confluence :
        Opérations S3 - https://confluence.epfl.ch:8443/pages/viewpage.action?pageId=95356742
        Documentation - https://confluence.epfl.ch:8443/pages/viewpage.action?pageId=99188910                                

#>
param([string]$targetEnv, 
      [string]$targetTenant, 
      [string]$action, 
      [string]$unitOrSvcID,  # On peut aussi y trouver un numéro de projet s'il s'agit du tenant Research
      [string]$friendlyName, 
      [string]$linkedTo, 
      [string]$bucketName, 
      [string]$userType, 
      [string]$enabled, 
      [string]$bucketTag,       # Présent mais pas utilisé pour le moment et pas non plus dans la roadmap Scality 7.5
      [switch]$status)

# Chargement du module PowerShell
Import-Module AWSPowerShell

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

# Chargement des fichiers propres à XaaS S3
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "S3", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "S3", "NameGeneratorS3.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "S3", "ScalityWebConsoleAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "S3", "ScalityAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configXaaSS3 = [ConfigReader]::New("config-xaas-s3.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE              = "create"
$ACTION_DELETE              = "delete"
$ACTION_REGEN_KEYS          = "regenKeys"
$ACTION_VERSIONING          = "versioning"
$ACTION_LINKED_BUCKETS      = "linkedBuckets"
$ACTION_GET_USERS           = "getUsers"
$ACTION_BUCKET_EXISTS       = "bucketExists"
$ACTION_BUCKET_IS_EMPTY     = "bucketIsEmpty"
$ACTION_GET_BUCKETS         = "getBuckets"
$ACTION_GET_BUCKETS_USAGE   = "getBucketsUsage"


<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le code.

	IN  : $notifications-> Dictionnaire
	IN  : $targetEnv	-> Environnement courant
	IN  : $targetTenant	-> Tenant courant
#>
function handleNotifications
{
	param([System.Collections.IDictionary] $notifications, [string]$targetEnv, [string]$targetTenant)

	# Parcours des catégories de notifications
	ForEach($notif in $notifications.Keys)
	{
		# S'il y a des notifications de ce type
		if($notifications.$notif.count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications.$notif | Sort-Object| Get-Unique

			$valToReplace = @{}

			switch($notif)
			{

				# ---------------------------------------
				# Erreur dans la récupération de stats d'utilisation pour un Bucket
				'bucketUsageError'
				{
                    $valToReplace.bucketList = ($uniqueNotifications -join "</li>`n<li>")
                    $valToReplace.nbBuckets = $uniqueNotifications.count
					$mailSubject = "Warning - S3 - Usage info not found for {{nbBuckets}} Buckets"
					$templateName = "xaas-s3-bucket-usage-error"
				}
			

				default
				{
					# Passage à l'itération suivante de la boucle
					$logHistory.addWarningAndDisplay(("Notification '{0}' not handled in code !" -f $notif))
					continue
				}

			}

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			$notificationMail.send($mailSubject, $templateName, $valToReplace)

		} # FIN S'il y a des notifications pour la catégorie courante

	}# FIN BOUCLE de parcours des catégories de notifications
}


<#
-------------------------------------------------------------------------------------
	BUT : Supprime un bucket S3

    IN  : $scality      -> Objet de la classe ScalityAPI et qui permet d'accéder au stockage S3
    IN  : $bucketName   -> Nom du bucket à supprimer
#>
function deleteBucket([ScalityAPI]$scality, [string]$bucketName)
{
    <# Parcours des policies dans lesquelles le bucket est défini. En théorie, il ne devrait y avoir que 2 policies :
    - pour l'accès RO
    - pour l'accès RW
    #>
    ForEach($s3Policy in $scality.getBucketPolicyList($bucketName))
    {
        $logHistory.addLine("Processing Policy {0}..." -f $s3Policy.PolicyName)

        # Si c'est le dernier Bucket dans la policy, on peut effacer celle-ci
        if($scality.onlyOneBucketInPolicy($s3Policy.PolicyName))
        {
            
            $logHistory.addLine("- Bucket {0} is the last in Policy" -f $bucketName)

            <# Parcours des utilisateurs qui sont référencés dans la policy. En théorie, il ne devrait 
                y avoir que 2 utilisateurs: 
                - un pour l'accès RO
                - un pour l'accès RW
            #>
            ForEach($s3User in $scality.getPolicyUserList($s3Policy.policyName))
            {
                # On supprime l'utilisateur de la policy
                $logHistory.addLine("- Removing User {0} from Policy..." -f $s3User.UserName)
                $scality.removeUserFromPolicy($s3Policy.PolicyName, $s3User.UserName)

                # On supprime l'utilisateur tout court !
                $logHistory.addLine("- Deleting User {0}..." -f $s3User.UserName)
                $scality.deleteUser($s3User.UserName)
            }

            # Suppression de la policy
            $logHistory.addLine("- Deleting Policy...")
            $scality.deletePolicy($s3Policy.PolicyName)
        }
        else # Ce n'est pas le dernier bucket de la policy, c'est qu'il est lié à au moins un autre bucket
        {
            $logHistory.addLine("- Removing Bucket {0} from Policy..." -f $bucketName)
            # on supprime simplement le bucket de la policy
            $s3Policy = $scality.removeBucketFromPolicy($s3Policy.PolicyName, $bucketName)
        }

    }# FIN BOUCLE de parcours des Policies du Bucket 

    # Effacement du bucket
    $scality.deleteBucket($bucketName)
}

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-s3', $global:LOGS_FOLDER, 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications=@{
                        bucketUsageError = @()
                    }
                                                
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet pour communiquer avec Scality
    $scality = [ScalityAPI]::new($configXaaSS3.getConfigValue(@($targetEnv, "server")),
                                 $configXaaSS3.getConfigValue(@($targetEnv, $targetTenant, "credentialProfile")),
                                 $configXaaSS3.getConfigValue(@($targetEnv, $targetTenant, "webConsoleUser")),
                                 $configXaaSS3.getConfigValue(@($targetEnv, $targetTenant, "webConsolePassword")),
                                 $configXaaSS3.getConfigValue(@($targetEnv, "isScality")))

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $scality.activateDebug($logHistory)    
    }
    

    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)


    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau bucket 
        $ACTION_CREATE {

            $doCleaningIfError = $true
            # S'il faut lier à un bucket, on contrôle qu'il existe bien
            if(($linkedTo -ne "") -and (!($scality.bucketExists($linkedTo))))
            {
                $doCleaningIfError = $false
                Throw ("Bucket to link to ({0}) doesn't exists" -f $linkedTo)
            }

            # Pour stocker les infos du nouveau bucket
            $bucketInfos = @{}

            $nameGeneratorS3 = [NameGeneratorS3]::new($unitOrSvcID,  $friendlyName)

            $bucketInfos.bucketName = $nameGeneratorS3.getBucketName()
            $bucketInfos.serverName = $configXaaSS3.getConfigValue(@($targetEnv, "server"))

            $logHistory.addLine("Creating bucket {0}..." -f $bucketInfos.bucketName)

            # Création du bucket
            $scality.addBucket($bucketInfos.bucketName) | Out-Null

            $bucketInfos.access = @{}
            
            # Si le nouveau bucket doit être "standalone"
            if($linkedTo -eq "")
            {
                
                # Parcours des types d'accès
                ForEach($accessType in $global:XAAS_S3_ACCESS_TYPES)
                {
                    $bucketInfos.access.$accessType = @{}

                    $logHistory.addLine("Creating element for {0} access... " -f $accessType)

                    # Génération des noms et stockage dans la structure
                    $bucketInfos.access.$accessType.userName = $nameGeneratorS3.getUserOrPolicyName($accessType, 'usr')
                    $bucketInfos.access.$accessType.policyName = $nameGeneratorS3.getUserOrPolicyName($accessType, 'pol')

                    # Création de l'utilisateur
                    $logHistory.addLine("- User {0}" -f $bucketInfos.access.$accessType.userName)
                    $s3User = $scality.addUser($bucketInfos.access.$accessType.userName)
                    $bucketInfos.access.$accessType.userArn = $s3User.Arn

                    # Génération des clefs d'accès
                    $logHistory.addLine("- User keys for {0}" -f $bucketInfos.access.$accessType.userName)
                    $userKey = $scality.regenerateUserAccessKey($bucketInfos.access.$accessType.userName)
                    $bucketInfos.access.$accessType.accessKeyId = $userKey.AccessKeyId
                    $bucketInfos.access.$accessType.secretAccessKey = $userKey.SecretAccessKey

                    # Création de la policy
                    $logHistory.addLine("- Policy {0}" -f $bucketInfos.access.$accessType.policyName)
                    $s3Policy = $scality.addPolicy($bucketInfos.access.$accessType.policyName, $bucketInfos.bucketName, $accessType)
                    $bucketInfos.access.$accessType.policyArn = $s3Policy.Arn
                    

                    # Ajout de l'utilisateur à la policy 
                    $logHistory.addLine("- Adding User to Policy... ")
                    $scality.addUserToPolicy($bucketInfos.access.$accessType.policyName, $bucketInfos.access.$accessType.userName)

                }# FIN BOUCLE de parcours des types d'accès 

            }
            else # Le Bucket doit être link à un autre
            {

                # Parcours des types d'accès
                ForEach($accessType in $global:XAAS_S3_ACCESS_TYPES)
                {
                    $bucketInfos.access.$accessType = @{}

                    # Recherche de la policy pour le type d'accès courant
                    $s3Policy = $scality.getBucketPolicyForAccess($linkedTo, $accessType)

                    # Ajout du bucket à la policy 
                    $logHistory.addLine("Adding Bucket to Policy {0}..." -f $s3Policy.PolicyName)
                    $s3Policy = $scality.addBucketToPolicy($s3Policy.policyName, $bucketInfos.bucketName)

                    $bucketInfos.access.$accessType.PolicyArn = $s3Policy.Arn
                    $bucketInfos.access.$accessType.policyName = $s3Policy.PolicyName
                    
                }
                
            }# FIN SI Le bucket doit être link à un autre

            $output.results +=  $bucketInfos
        

        }# FIN Action Create


        # -- Effacement d'un bucket
        $ACTION_DELETE {

            # Suppression du bucket
            deleteBucket -scality $scality -bucketName $bucketName
        }


        # -- Génération de nouvelles clefs
        $ACTION_REGEN_KEYS {

            # On détermine pour quels types d'accès il faut regénérer les clefs
            if($userType -eq 'all')
            {
                $toRegen = @('ro', 'rw')
            }
            else
            {
                $toRegen = @($userType)
            }

            # Parcours des types d'utilisateurs pour lesquels regénérer les clefs
            ForEach($userAccessType in $toRegen)
            {

                # Recherche de la policy qui gère le type d'accès demandé
                $s3Policy = $scality.getBucketPolicyForAccess($bucketName, $userAccessType)

                # Si on n'a pas trouvé
                if($null -eq $s3Policy)
                {
                    Throw ("No '{0}' policy found for bucket '{1}'" -f $userAccessType, $bucketName)
                }

                $logHistory.addLine(("'{0}' Policy for Bucket is: {1}" -f $userAccessType, $s3Policy.PolicyName))

                # Recherche de l'utilisateur dans la Policy
                $s3User = $scality.getPolicyUserList($s3Policy.PolicyName)
                

                # Si aucun utilisateur remonté
                if($s3User.Count -eq 0)
                {
                    Throw("No user found in '{0}' Policy '{1}'" -f $userName, $s3Policy.PolicyName)
                }
                # Trop d'utilisateurs remontés !
                elseif ($s3User.Count -gt 1)
                {
                    Throw ("Too many '{0}' users found ({1}) in Policy '{2}'" -f $userType, $s3User.Count, $s3Policy.PolicyName)
                }
                
                $logHistory.addLine("Regenerating keys for user {0}... " -f $s3User[0].UserName)
                # On lance la regénération des clefs pour l'utilisateur
                $newKeys = $scality.regenerateUserAccessKey($s3User[0].UserName)

                $output.results +=  @{userName = $s3User[0].UserName
                                    userArn = $s3User[0].Arn
                                    accessKeyId = $newKeys.AccessKeyId
                                    secretAccessKey = $newKeys.SecretAccessKey}
            

            }# FIN Boucle de parcours des types d'accès utilisateurs à regénérer
        }


        # -- Changement de l'état du versioning ou récupération de l'état
        $ACTION_VERSIONING {
            # Si on veut changer l'état
            if(!$status)
            {
                $scality.setBucketVersioning($bucketName, ($enabled | ConvertFrom-Json))
            }

            # Dans tous les cas, on retourne l'état du versioning
            $output.results += @{enabled =$scality.bucketVersioningEnabled($bucketName)}

        }


        # -- Renvoi des buckets liés
        $ACTION_LINKED_BUCKETS {
            # Recherche de la policy RW du Bucket (on pourrait aussi prendre l'autre)
            $s3Policy = $scality.getBucketPolicyForAccess($bucketName, "rw")
            $logHistory.addLine("Looking for linked Buckets in Policy '{0}'..." -f $s3Policy.PolicyName)

            # Recherche des buckets dans la policy
            ForEach($s3BucketName in $scality.getPolicyBucketList($s3Policy.PolicyName))
            {
                # on fait en sorte de ne pas remettre dans la liste le bucket pour lequel on recherche
                if($s3BucketName -ne $bucketName)
                {
                    $output.results += @{bucketName = $s3BucketName}
                }
            }
            
        }


        # -- Renvoi des utilisateurs 
        $ACTION_GET_USERS {
            <# Parcours des policies dans lesquelles le bucket est défini. En théorie, il ne devrait y avoir que 2 policies :
            - pour l'accès RO
            - pour l'accès RW
            #>
            ForEach($s3Policy in $scality.getBucketPolicyList($bucketName))
            {
                $logHistory.addLine("Looking for users in Policy '{0}'..." -f $s3Policy.PolicyName)
                <# Parcours des utilisateurs qui sont référencés dans la policy. En théorie, il ne devrait 
                    y avoir que 2 utilisateurs: 
                    - un pour l'accès RO
                    - un pour l'accès RW
                #>
                ForEach($s3User in $scality.getPolicyUserList($s3Policy.policyName))
                {
                    # Ajout des infos de l'utilisateur
                    $output.results += @{userName = $s3User.UserName
                                         userArn = $s3User.Arn}
                }
            }
        }


        # -- Savoir si un bucket existe
        $ACTION_BUCKET_EXISTS {
            # On essaie de chercher le bucket pour voir s'il existe
            $output.results += ($null -ne $scality.getBucket($bucketName))
        }


        # -- Savoir si un bucket est vide
        $ACTION_BUCKET_IS_EMPTY {
            # Si la liste des objets ne contient rien, c'est que le bucket est vide.
            $output.results += ($scality.getBucketObjectList($bucketName).Count -eq 0)
        }


        # -- Liste des buckets
        $ACTION_GET_BUCKETS {

            # Récupération de la list des buckets et on ne prend ensuite que le nom du bucket
            $scality.getBucketList() | ForEach-Object {
                $output.results += $_.BucketName
            }
        }

        #-- Taille des buckets
        $ACTION_GET_BUCKETS_USAGE {

            # Récupération de la liste des buckets et parcours
            ForEach($bucket in $scality.getBucketList())
            {

                $logHistory.addLine( ("Processing bucket {0}" -f $bucket.bucketName) )

                try
                {
                    # Récupération des infos d'utilisation
                    $usageInfos = $scality.getBucketUsageInfos($bucket.BucketName)
                    # Ajout du nom du bucket
                    $usageInfos.bucketName = $bucket.BucketName

                    $output.results += $usageInfos
                }
                catch # Gestion des erreurs
                {
                    $logHistory.addLine( ("Error getting bucket {0} usage infos" -f $bucket.bucketName) )
                    $notifications.bucketUsageError += $bucket.BucketName
                }
                
            }# FIN BOUCLE de parcours des Buckets
        }
    }

    $logHistory.addLine("Script execution done!")


    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

    # Gestion des erreurs s'il y en a
    handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant
    

}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

    # Si on était en train de créer un bucket et qu'on peut faire le cleaning
    if(($action -eq $ACTION_CREATE) -and $doCleaningIfError)
    {
        # On efface celui-ci pour ne rien garder qui "traine"
        $logHistory.addLine(("Error while creating Bucket '{0}', deleting it so everything is clean. Error was: {1}" -f $bucketInfos.bucketName, $errorMessage))

        # Suppression du bucket
        deleteBucket -scality $scality -bucketName $bucketInfos.bucketName
    }

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
    # On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
    $errorMessage = $errorMessage -replace "`n", "<br>"

	# Création des informations pour l'envoi du mail d'erreur
	$valToReplace = @{	
        scriptName = $MyInvocation.MyCommand.Name
        computerName = $env:computername
        parameters = (formatParameters -parameters $PsBoundParameters )
        error = $errorMessage
        errorTrace =  [System.Net.WebUtility]::HtmlEncode($errorTrace)
    }

    # Envoi d'un message d'erreur aux admins 
    $notificationMail.send("Error in script '{{scriptName}}'", "global-error", $valToReplace) 
}