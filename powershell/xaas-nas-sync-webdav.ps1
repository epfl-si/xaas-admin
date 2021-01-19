<#
USAGES:
    xaas-nas-sync-webdav.ps1 -targetEnv prod|test|dev
#>
<#
    BUT 		: Script lancé par une tâche planifiée, afin de créer le nécessaire sur la passerelle WebDAV
                    pour que les volumes concernés puissent être accédés via WebDAV
              
	DATE 	: Octobre 2020
    AUTEUR 	: Lucien Chaboudez
    
    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.
#>
param([string]$targetEnv)

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

# Chargement des fichiers propres au NAS NetApp
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "NameGeneratorNAS.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configVra = [ConfigReader]::New("config-vra.json")
$configNAS = [ConfigReader]::New("config-xaas-nas.json")


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------





# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Nom du dossier Webdav en local sur ce serveur 
$global:WEBDAV_LOCAL_DIRECTORY = "C:\webdavroot"
$global:WEBDAV_SITE_NAME = "webdav"
# Compte qui doit être en "ReadOnly" sur tous les shares accédés en WebDAV
$global:WEBDAV_AD_USER = "INTRANET\nas-webdav-user"


# -------------------------------------------- FONCTIONS ---------------------------------------------------

<#
   BUT : Permet de savoir si un "virtual directory" exists

   IN  : $virtualDirPath   -> Chemin du dossier virtuel dont on veut savoir s'il existe
   
   RET : $true|$false
#>
function virtualDirectoryExists([string] $virtualDirPath)
{
   return (Get-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME | Where-Object { $_.path -like "/$virtualDirPath" }).Count -gt 0  
}


# -----------------------------------------------------------------------------------------
<#
   BUT : Contrôle les droits sur un share et s'assure que ceux-ci sont bons pour que l'accès
        en webDAV (ou plutôt la création du lien sur le share) fonctionne

   IN  : $netapp        -> Objet de la classe NetAppAPI permettant d'accéder au NetApp
   IN  : $vServerName   -> Nom du vServer
   IN  : $shareName     -> Nom du share
#>
function checkShareALCs([NetAppAPI]$netapp, [string]$vServerName, [string]$shareName)
{
    # Récupération de la SVM
    $svm = $netapp.getSVMByName($vServerName)

    # Si l'ACLs pour l'utilisateur webDAV n'existe pas (on admet que si elle existe, elle a les bons droits)
    if( ($netapp.getCIFSShareACLList($svm, $shareName) | Where-Object { $_.user_or_group -eq $global:WEBDAV_AD_USER }).count -eq 0)
    {
        $logHistory.addLineAndDisplay((">> ACL doesn't exists for user '{0}', creating it..." -f $global:WEBDAV_AD_USER))

        $netapp.addCIFSShareACL($svm, $shareName, $global:WEBDAV_AD_USER, [NetAppSharePermission]::read)
    }
    else
    {
        $logHistory.addLineAndDisplay((">> ACL exists for user '{0}'" -f $global:WEBDAV_AD_USER))
    }
}


# -----------------------------------------------------------------------------------------

<# 
   BUT : Créé/efface un "virtual directory" représentant un share
   
   IN  : $vServerName      -> Nom du vServer
   IN  : $shareName        -> Le nom du share
   IN  : $exists           -> $true|$false pour dire si le "virtual directory" doit exister ou pas
   
#>
function updateShareVirtuaDirectory([NetAppAPI]$netapp, [string] $vServerName, [string] $shareName, [bool] $exists)
{
 
   # Génération du chemin UNC pour le dossier distant.
   $remotePath = ("\\{0}\{1}" -f $vServerName, $shareName)
   # Génération du nom du "virtual directory" local
   $virtualDirectoryPath = ("{0}/{1}" -f $vServerName, $shareName)
   
   # Génération du chemin jusqu'au dossier local bidon
   $localVServerPath = Join-Path $global:WEBDAV_LOCAL_DIRECTORY $vServerName
   $tmpFolderPath = join-Path $localVServerPath $shareName
   
   # Si on doit créer le "virtual directory"
   if($exists -eq $true)
   {
        # Si le "virtual directory" n'existe pas, 
        if(!(virtualDirectoryExists -virtualDirPath $virtualDirectoryPath))
        {
            <# Si le dossier distant existe, 
                REMARQUE :
                Pour que ce test puisse fonctionner, il faut que l'utilisteur employé pour exécuter ce script soit dans le groupe "local admin"
                du serveur CIFS distant.
            #>
            if(Test-Path $remotePath)
            {
                $logHistory.addLineAndDisplay(("> Checking ACLs for share '{0}' on vServer '{1}'..." -f $shareName, $vServerName))
                checkShareALCs -netapp $netapp -vServerName $vServerName -shareName $shareName

                $logHistory.addLineAndDisplay(("> Creating virtual directory for share '{0}' on vServer '{1}'..." -f $shareName, $vServerName))

                # Création du "virtual directory" associé dans WebDav
                New-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME -Name $virtualDirectoryPath -physicalPath $remotePath -ErrorVariable errorOutput -ErrorAction:SilentlyContinue | Out-Null
            
                $counters.inc('ShareVirtualDirCreated')
            }
            else # si erreur,
            {
                # Ajout du "remote path" qui pose problème
                $notifications.shareVirtualDirError += $remotePath
            }
         
        } # FIN Si le virtual directory n'existe pas
    }
    else # On doit supprimer le "virtual directory"
    {
   
        # Si le "virtual directory" existe,
        if(virtualDirectoryExists -virtualDirPath $virtualDirectoryPath)
        {
            <# ATTENTION, cette partie de code peut sembler bizarre, surtout quand on voit qu'il faut créer
            un dossier temporaire, modifier le "virtual directory", ensuite supprimer celui-ci et fau final
            effacer le dossier temporair qui avait été créé. C'est con, c'est pas propre mais y'a pas d'autre 
            solution. Pourquoi? parce que lorsque l'on veut supprimer un "virtual folder" qui a du contenu
            "sous lui-même", la commande demande une confirmation. Il y a bien la possibilité de mettre 
            -confirm:$false à la fin de la commande mais celle-ci est buggée et donc rien n'est pris en compte.
            La seule solution trouvée a été ce workaround de modifier le "virtual directory" pour le faire pointer
            vers un dossier vide afin de pouvoir le supprimer.
            #>
        
            $logHistory.addLineAndDisplay(("> Deleting virtual directory for share '{0}' on vServer '{1}'..." -f $shareName, $vServerName))

            # Création d'un dossier local bidon
            if(!(Test-path -Path $tmpFolderPath)) 
            { 
                New-Item -Path $localVServerPath -ItemType "Directory" -Name $shareName | Out-Null
            }
            
            # Modification du "Virtual directory" existant pour le faire pointer sur le dossier temporaire (-Force pour modifier)
            New-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME -Name $virtualDirectoryPath -physicalPath $tmpFolderPath -Force | Out-Null
            
            # Suppression du "virtual directory" associé dans WebDav (pour une raison obscure, il faut passer l'application alors qu'il n'y en n'a pas...)
            Remove-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME -Name $virtualDirectoryPath -Application "/" | Out-Null
            
            # Suppression du dossier temporaire crée
            if(Test-path -Path $tmpFolderPath) 
            { 
                Remove-Item -Path $tmpFolderPath | Out-Null
            }
            
            $counters.inc('ShareVirtualDirDeleted')
        }# FIN SI le "virtual directory" existe 
      
    }# FIN SI on doit supprimer le "virtual directory"
   
}


# -----------------------------------------------------------------------------------------

<#
   BUT : Créé/efface un "virtual directory" représentant un vServer. 
   
   IN  : $vServerName      -> Nom du vServer
   IN  : $exists           -> $true|$false pour dire si le "virtual directory" doit exister ou pas
   
#>
function updateVServerVirtualDirectory([NetAppAPI]$netapp, [string] $vServerName, [bool] $exists)
{
    
    # Génération du chemin jusqu'au dossier local
    $localVServerPath = Join-Path $global:WEBDAV_LOCAL_DIRECTORY $vServerName
    
    # Si on doit créer le "virtual directory"
    if($exists -eq $true)
    {
        # Création physique du dossier si n'existe pas
        if(! (Test-path -Path $localVServerPath))
        {
            $logHistory.addLineAndDisplay(("> Creating physical directory for vServer '{0}'..." -f $vServerName))
            # Création du dossier
            New-Item -Path $global:WEBDAV_LOCAL_DIRECTORY -ItemType "Directory" -Name $vServerName | Out-Null
        }
        else
        {
            $logHistory.addLineAndDisplay(("> Physical directory for vServer '{0}' already exists" -f $vServerName))
        }
        
        # Si le "virtual directory" n'existe pas, 
        if(!(virtualDirectoryExists -virtualDirPath $vServerName))
        {
            $logHistory.addLineAndDisplay(("> Creating virtual directory for vServer '{0}'..." -f $vServerName))
            # Création du "virtual directory" associé dans WebDav
            New-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME -Name $vServerName -physicalPath $localVServerPath | Out-Null
            
            $counters.inc('vServerVirtualDirCreated')
        }
        else
        {
            $logHistory.addLineAndDisplay(("> Virtual directory for vServer '{0}' already exists" -f $vServerName))
        }
    }
    else # On doit supprimer le dossier 
    {
        $logHistory.addLineAndDisplay(("> Deleting sub-virtual-directories for vServer '{0}'..." -f $vServerName))
        # Effacement des "sous-dossiers" s'il y en a
        foreach($virtualFolder in (Get-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME | Where-Object { $_.path -like "/$vServerName/*" }))
        {
            # Extraction des infos. Le chemin est sous la forme /vServer/share
            $null, $vServer, $shareName = $virtualFolder.path.split('/')
         
            updateShareVirtuaDirectory -netapp $netapp -vServerName $vServerName -shareName $shareName -exists $false
            
        }# FIN BOUCLE d'effacement des "sous-dossiers"
        
    
        # Si le "virtual directory" existe,
        if(virtualDirectoryExists -virtualDirPath $vServerName)
        {
            $logHistory.addLineAndDisplay(("> Deleting virtual directory for vServer '{0}'..." -f $vServerName))

            # Suppression du "virtual directory" associé dans WebDav (pour une raison obscure, il faut passer l'application alors qu'il n'y en n'a pas...)
            Remove-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME -Name $vServerName -Application "\" | Out-Null
            
            $counters.inc('vServerVirtualDirDeleted')
        }
        
        # Suppression physique du dossier si existe
        if(Test-path -Path $localVServerPath)
        {
            $logHistory.addLineAndDisplay(("> Deleting physical directory for vServer '{0}'..." -f $vServerName))
            # Création du dossier
            Remove-Item -Path $localVServerPath | Out-Null
        }
        
    }# FIN SI on doit supprimer le dossier 
    
}


# -----------------------------------------------------------------------------------------
<#
   BUT : Cherche et renvoie la liste des shares WebDAV à créer

   IN  : $vra       -> Objet pour accéder à vRA
   IN  : $netapp    -> Objet pour accéder au NAS NetApp

   RET : Tableau avec chaque élément ayant :
            .vserver        -> nom du vServer
            .share          -> nom du share
#>
function getWebDAVShareList([vRAAPI]$vra, [NetAppAPI]$netapp)
{

    $shareList = @()
    # Parcours des Business Groups
    $vra.getBGList() | ForEach-Object {

        $logHistory.addLineAndDisplay("Processing BG {0} ..." -f $_.Name)
        $counters.inc('BGProcessed')
        
        # Parcours des Volumes NAS se trouvant dans le Business Group
        $vra.getBGItemList($_, $global:VRA_XAAS_NAS_DYNAMIC_TYPE) | ForEach-Object {

            $counters.inc('VolProcessed')

            # On regarde si le volume doit être accédé en WebDAV
            if( (getvRAObjectCustomPropValue -object $_ -customPropName $global:VRA_XAAS_NAS_CUSTOM_PROPERTY_WEBDAV_ACCESS) -eq $true)
            {
                # Recherche du volume
                $vol = $netapp.getVolumeByName($_.Name)

                # Recherche des shares pour le volume donné et ajout à la liste
                $netapp.getVolCIFSShareList($_) | ForEach-Object {
                    $shareList += @{
                        vserver = $vol.svm.name
                        share = $_.name
                    }
                }

                $counters.inc('VolWebDAVProcessed')
            }
            else # Pas d'accès en WebDAV
            {
                $counters.inc('VolNoWebDAVProcessed')
            }

        } # FIN BOUCLE de parcours des Volumes NAS du BG

    }# FIN BOUCLE de parcours des Business Groups

    return $shareList
}


<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le caode.

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
		if($notifications[$notif].count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications[$notif] | Sort-Object| Get-Unique

			$valToReplace = @{}

			switch($notif)
			{

				# ---------------------------------------
				# Pas possible de créer le dossier virtuel pour certains shares
				'shareVirtualDirError'
				{
					$valToReplace.dirList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Warning - WebDAV virtual directories not created for some shares"
					$templateName = "webdav-virtual-dir-not-created"
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


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    
    $logName = 'xaas-nas-sync-webdav-{0}' -f $targetEnv.ToLower()
    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new($logName, (Join-Path $PSScriptRoot "logs"), 30)

    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:NAS_MAIL_TEMPLATE_FOLDER, `
                                                $global:NAS_MAIL_SUBJECT_PREFIX , $valToReplace)

    # Contrôle que l'utilisateur pour exécuter le script soit correct
    $domain, $username = $global:WEBDAV_AD_USER -split '\\'
    if($username -ne $env:USERNAME)
    {
        Throw ("Script must be executed with 'INTRANET\{0}' user, is currently executed with 'INTRANET\{1}'" -f $username, $env:USERNAME)
    }

    # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $counters = [Counters]::new()
    $counters.add('BGProcessed', '# BG Processed')
    $counters.add('VolProcessed', '# Volumes processed')
    $counters.add('VolWebDAVProcessed', '# Volumes with WebDAV processed')
    $counters.add('VolNoWebDAVProcessed', '# Volumes without WebDAV processed')
    # Shares
    $counters.add('ShareVirtualDirCreated', '# Share virtual dir created')
    $counters.add('ShareVirtualDirDeleted', '# Share virtual dir deleted')
    # vServer
    $counters.add('vServerVirtualDirCreated', '# vServer virtual dir created')
    $counters.add('vServerVirtualDirDeleted', '# vServer virtual dir deleted')
    
    # Création de l'objet pour se connecter aux clusters NetApp
    $netapp = [NetAppAPI]::new($configNAS.getConfigValue(@($targetEnv, "serverList")),
                                $configNAS.getConfigValue(@($targetEnv, "user")),
                                $configNAS.getConfigValue(@($targetEnv, "password")))

            
    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = "all"
	}
                                                
    <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications=@{
        shareVirtualDirError = @()
    }

    # -------------------------------------------------------------------------------------------

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))

    $logHistory.AddlineAndDisplay("Importing WebAdministration module... ")
    Import-Module WebAdministration


    $tenantToProcess = @(
        $global:VRA_TENANT__EPFL
        $global:VRA_TENANT__ITSERVICES
    )

    # # Liste pour les vServer+shares traités (renvoyés par le Web Service)
    $vServerDoneList = @{}

    # Parcours des tenants depuis lesquels il faut récupérer la liste des shares WebDAV à créer
    ForEach($targetTenant in $tenantToProcess)
    {
        # Création d'une connexion au serveur vRA pour accéder à ses API REST
        $vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "infra", "server"), 
                                $targetTenant, 
                                $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "user"), 
                                $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "password"))

        # Récupération des informations sur les FS qui doivent être accédés en WebDav 
        $webdavShareList = [Array](getWebDAVShareList -vra $vra -netapp $netapp)

        # Parcours des lignes renvoyées par le Web Service
        foreach($webdavInfos in $webdavShareList)
        {
            $logHistory.addlineAndDisplay(("Processing share '{0}' on '{1}' server..." -f $webdavInfos.share, $webdavInfos.vserver))

            # Si on n'a pas encore traité ce vServer, 
            if($vServerDoneList.Keys -notcontains $webdavInfos.vserver)
            {
                # Mise à jour du vServer
                updateVServerVirtualDirectory -netapp $netapp -vServerName $webdavInfos.vserver -exists $true

                $vServerDoneList.($webdavInfos.vserver) = @()
            }# FIN SI on n'a pas encore traité le vServer 

            # Mise à jour du share 
            updateShareVirtuaDirectory -netapp $netapp -vServerName $webdavInfos.vserver -shareName $webdavInfos.share -exists $true

            # Ajout du share dans la liste 
            $vServerDoneList.($webdavInfos.vserver) += $webdavInfos.share

        }# FIN BOUCLE de parcours des lignes renvoyées

        # On peut se déconnecter du tenant courant
        $vra.disconnect()
    }
    


    # -------------------------------------------
    # Maintenant que l'on a traité les shares qui existent, on doit supprimer ceux qui n'existent plus.

    # TODO: Décommenter la partie ci-dessous lorsque la migration NAS sera terminée
    # # Recherche de la liste des "Virtual directory" qui existent dans la config WebDav
    # $existingVirtualDirList = Get-WebVirtualDirectory -Site $global:WEBDAV_SITE_NAME 

    # # parcours de la liste
    # foreach($existingVirtualDirInfos in $existingVirtualDirList)
    # {
    #     $logHistory.addlineAndDisplay(("Processing virtual directory '{0}'..." -f $existingVirtualDirInfos.path))
    #     # Le path est au format /<vServer>[/shareName]
        
    #     # Extraction des infos 
    #     $null, $vServerName, $shareName = $existingVirtualDirInfos.path.split('/')
        
    #     # Si c'est un Virtual Directory qui représente un share
    #     if($null -ne $shareName)
    #     {
    #         # Si le vServer ne devrait pas exister, 
    #         if($vServerDoneList.Keys -notcontains $vServerName)
    #         {
    #             $logHistory.addLineAndDisplay(("> Virtual directory for server '{0}' shouldn't exists, deleting it..." -f $vServerName))
    #             # On le supprime
    #             updateVServerVirtualDirectory -netapp $netapp -vServerName $vServerName -exists $false
                
    #         }
    #         # Le vServer doit exister,
    #         else
    #         {
    #             # Si le share ne doit pas exister, 
    #             if($vServerDoneList.$vServerName -notcontains $shareName)
    #             {
    #                 $logHistory.addLineAndDisplay(("> Virtual directory for share '{0}' on server '{1}' shouldn't exists, deleting it..." -f $shareName, $vServerName))
    #                 updateShareVirtuaDirectory -netapp $netapp -vServerName $vServerName -shareName $shareName -exists $false
                  
    #             }
    #         }# FIN Si le vServer doit exister
            
    #     }
    #     else # C'est un vServer qui est représenté
    #     {
    #         # Si le vServer ne devrait pas exister, 
    #         if($vServerDoneList.Keys -notcontains $vServerName)
    #         {
    #             $logHistory.addLineAndDisplay(("> Virtual directory for server '{0}' shouldn't exists, deleting it..." -f $vServerName))
    #             # On le supprime
    #             updateVServerVirtualDirectory -netapp $netapp -vServerName $vServerName -exists $false
              
    #         }
    #     }# FIN SI c'est un vServer qui est représenté
    
    # }# FIN BOUCLE de parcours de la liste des dossiers existants.

    # Affichage des compteurs
    $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

    # Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant


}
catch
{
    # Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

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