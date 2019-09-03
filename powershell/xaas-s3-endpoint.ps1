<#
USAGES:
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -unitOrSvcID <unitOrSvcID> -friendlyName <friendlyName> [-linkedTo <linkedTo>]
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action delete -bucketName <bucketName>
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action regenKeys -bucketName <bucketName> -userType (ro|rw)
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action versioning -bucketName <bucketName> -enabled (true|false)
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action versioning -bucketName <bucketName> -status
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action linkedBuckets -bucketName <bucketName>
    xaas-s3-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action getUsers -bucketName <bucketName>
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
param([string]$targetEnv, [string]$targetTenant, [string]$action, [string]$unitOrSvcID, [string]$friendlyName, [string]$linkedTo, [string]$bucketName, [string]$userType, [string]$enabled, [switch]$status)

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))

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
$ACTION_CREATE = "create"
$ACTION_DELETE = "delete"
$ACTION_REGEN_KEYS = "regenKeys"
$ACTION_VERSIONING = "versioning"
$ACTION_LINKED_BUCKETS = "linkedBuckets"
$ACTION_GET_USERS = "getUsers"


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
    $logHistory = [LogHistory]::new('xaas-s3', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet pour communiquer avec Scality
    $scality = [ScalityAPI]::new($configXaaSS3.getConfigValue($targetEnv, "server"), 
                                 $configXaaSS3.getConfigValue($targetEnv, $targetTenant, "credentialProfile"), 
                                 $configXaaSS3.getConfigValue($targetEnv, $targetTenant, "webConsoleUser"), 
                                 $configXaaSS3.getConfigValue($targetEnv, $targetTenant, "webConsolePassword"))


    


    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau bucket 
        $ACTION_CREATE {

            # S'il faut lier à un bucket, on contrôle qu'il existe bien
            if(($linkedTo -ne "") -and (!($scality.bucketExists($linkedTo))))
            {
                $output.error = "Bucket to link to ({0}) doesn't exists" -f $linkedTo
            }
            else
            {

                # Pour stocker les infos du nouveau bucket
                $bucketInfos = @{}

                $nameGeneratorS3 = [NameGeneratorS3]::new($unitOrSvcID,  $friendlyName)

                $bucketInfos.bucketName = $nameGeneratorS3.getBucketName()

                $logHistory.addLine("Creating bucket {0}..." -f $bucketInfos.bucketName)

                # Création du bucket
                $s3Bucket = $scality.addBucket($bucketInfos.bucketName)

                # Si le nouveau bucket doit être "standalone"
                if($linkedTo -eq "")
                {
                    $bucketInfos.access = @{}

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

                    # Recherche de la liste des policies pour le bucket auquel il faut link le nouveau 
                    ForEach($s3Policy in $scality.getBucketPolicyList($linkedTo))
                    {
                        # Ajout du bucket à la policy 
                        $logHistory.addLine("Adding Bucket to Policy {0}..." -f $s3Policy.PolicyName)
                        $s3Policy = $scality.addBucketToPolicy($s3Policy.policyName, $bucketInfos.bucketName)
                    }
                }

                $output.results +=  $bucketInfos
            }
        }


        # -- Effacement d'un bucket
        $ACTION_DELETE {

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


        # -- Génération de nouvelles clefs
        $ACTION_REGEN_KEYS {

            # Recherche de la policy qui gère le type d'accès demandé
            $s3Policy = $scality.getBucketPolicyForAccess($bucketName, $userType)
            $logHistory.addLine(("'{0}' Policy for Bucket is: {1}" -f $userType, $s3Policy.PolicyName))

            # Recherche de l'utilisateur dans la Policy
            $s3User = $scality.getPolicyUserList($s3Policy.PolicyName)
            

            # Si aucun utilisateur remonté
            if($s3User.Count -eq 0)
            {
                $output.error = "No user found in '{0}' Policy '{1}'" -f $userName, $s3Policy.PolicyName

                $logHistory.addLine($output.error)
            }
            # Trop d'utilisateurs remontés !
            elseif ($s3User.Count -gt 1)
            {
                $output.error = "Too many '{0}' users found ({1}) in Policy '{2}'" -f $userType, $s3User.Count, $s3Policy.PolicyName
                $logHistory.addLine($output.error)
            }
            else 
            {
                $logHistory.addLine("Regenerating keys for user {0}... " -f $s3User[0].UserName)
                # On lance la regénération des clefs pour l'utilisateur
                $newKeys = $scality.regenerateUserAccessKey($s3User[0].UserName)

                $output.results +=  @{userName = $s3User[0].UserName
                                     userArn = $s3User[0].Arn
                                     accessKeyId = $newKeys.AccessKeyId
                                     secretAccessKey = $newKeys.SecretAccessKey}
            }

            
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


        # Renvoi des utilisateurs 
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
    }

    # Affichage du résultat
    displayJSONOutput -output $output

}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
	
	# Envoi d'un message d'erreur aux admins 
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant ""
	$mailMessage = getvRAMailContent -content ("<b>Script:</b> {0}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Net.WebUtility]::HtmlEncode($errorTrace))

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $mailMessage    
}