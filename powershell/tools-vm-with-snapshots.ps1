<#
USAGES:
    tools-vm-with-snapshots.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research
    tools-vm-with-snapshots.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research [-sendNotifMail -maxAgeDays <maxAgeDays>]
    tools-vm-with-snapshots.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research -projectList <projectList>
    tools-vm-with-snapshots.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research -projectRegex <projectRegex>
#>
<#
    BUT 		: Script permettant d'afficher les VMs qui ont un snapshot, soit pour tous les BG, soit pour une
                    liste de BG donnée (séparée par des virgules), soit pour les BG dont le nom match la regex passée
                    
	DATE 	: Mai 2021
    AUTEUR 	: Lucien Chaboudez
    
    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.

#>
param([string]$targetEnv, 
      [string]$targetTenant,
      [string]$projectList, # Liste des Projets, séparés par des virgules. Il faut mettre cette liste entre simple quotes ''
      [string]$projectRegex, # Expression régulière pour le filtre des noms de Projet. Il faut mettre entre simple quotes ''
      [int]$maxAgeDays, # Âge maximum des snapshots (en jours) à partir duquel on envoie un mail
      [switch]$sendNotifMail)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRA8API.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal   = [ConfigReader]::New("config-global.json")
$configVra 		= [ConfigReader]::New("config-vra8.json")


<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le caode.

	IN  : $notifications    -> Dictionnaire
	IN  : $targetEnv	    -> Environnement courant
	IN  : $targetTenant	    -> Tenant courant
#>
function handleNotifications([System.Collections.IDictionary] $notifications, [string]$targetEnv, [string]$targetTenant)
{

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
				# Groupe active directory manquants pour création des éléments pour Tenant EPFL
				'unknownMailboxes'
				{
					$valToReplace.mailList = ($uniqueNotifications -join "</li>`n<li>")
					
					$mailSubject = "Warning - VM Notification mail list "

					$templateName = "vm-incorrect-notification-mail-list"
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

try
{

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new(@('tools','vm-with-snapshots'), $global:LOGS_FOLDER, 120)
        
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

    # Objet pour pouvoir envoyer des mails de notification
    $valToReplace = @{
        targetEnv = $targetEnv
    }

    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                                                ($global:VRA_MAIL_SUBJECT_PREFIX_NO_TENANT -f $targetEnv), $valToReplace)

    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications = @{}
	$notifications.unknownMailboxes = @()

    $vra = [vRA8API]::new($configVra.getConfigValue(@($targetEnv, "infra",  $targetTenant, "server")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

    # Recherche de la liste des Projets en fonction des noms donnés
    $targetProjectList = $vra.getProjectList()

    # Si on doit filtrer sur des BG,
    if($projectList -ne "") 
    {
        # On transforme le paramètre en tableau
        $projectListNames = $projectList.split(",")

        $targetProjectList = $targetProjectList | Where-Object { $projectListNames -contains $_.name }
    }
    # Si on a passé une regex
    elseif($projectRegex -ne "")
    {
        $targetProjectList = $targetProjectList | Where-Object { $_.name -match $projectRegex }
    }

    # Liste des VM avec des snapshots
    [System.Collections.ArrayList]$vmWithSnap = @()
    
    $now = Get-Date

    if($sendNotifMail)
    {
        $mailFrom = ("noreply+{0}" -f $configGlobal.getConfigValue(@("mail", "admin")))
        $mailMessageTemplate = (Get-Content -Raw -Path ( Join-Path $global:MAIL_TEMPLATE_FOLDER "vm-with-old-snap.html" ))
        $mailSubject = "[IaaS] VMs with old snapshots"
    }
    

    # Parcours des BG
    Foreach($project in $targetProjectList)
    {
        # TODO: Continuer ici. Voir pour récupérer les déploiements depuis le blueprint id pour avoir le type => pas possible 
        # pour le moment d'avoir un type de déploiement. On dirait que le type "VMware Cloud Templates" regroupe tout... VM et types dynamiques, à confirmer
        $logHistory.addLineAndDisplay(("Processing Project '{0}'..." -f $project.name))
        $vmList = $vra.getProjectDeploymentList($project, $global:VRA_ITEM_TYPE_VIRTUAL_MACHINE)

        # Parcours des VM
        ForEach($vm in $vmList)
        {
            # TODO: Pour la partie récupération d'info de snapshot. A priori rien de dispo comme données dans
                # la partie REST. Et pas possible de récupérer la VM dans vSphere (pour avoir les snapshots) car on n'a pas son nom qui est retourné via REST...
            # Parcours des snapshots de la VM courante
            ForEach($snap in ($vm.resourceData.entries | Where-Object { $_.key -eq "SNAPSHOT_LIST"}).value.items)
            {

                # Récupération de la date de création
                $createDate = [DateTime]::parse(($snap.values.entries | Where-Object { $_.key -eq "SNAPSHOT_CREATION_DATE"}).value.value)
                # Calcul de l'âge du snapshot 
                $dateDiff = New-Timespan -start $createDate -end $now

                # Si on est en mode "notification"
                if($sendNotifMail)
                {

                    # Si le snapshot est trop âgé
                    if($dateDiff.days -ge $maxAgeDays)
                    {
                        $logHistory.addLineAndDisplay(("-> VM '{0}' has snapshot since {1} ({2} days)" -f $vm.name, $createDate.toString("dd.MM.yyyy HH:mm:ss"), $dateDiff.days))

                        # Recherche des adresses mail de notification et ajout d'une entrée par personne dans la liste
                        getvRAObjectNotifMailList -vRAvm $vm -mailPropName "ch.epfl.owner_mail" | Foreach-Object {
                            
                            # Si pas trouvé le mail
                            if($null -eq $_ -or $_ -eq "")
                            {
                                $logHistory.addWarningAndDisplay(("--> Empty mail found for VM '{0}'" -f $vm.name))
                            }
                            else
                            {
                                # Ajout au tableau avec les infos nécessaires pour envoyer les mails par la suite
                                $vmWithSnap.add([PSCustomObject]@{
                                    bgName = $project.name
                                    VM = $vm.name
                                    snapshotDate = $createDate.toString("dd.MM.yyyy HH:mm:ss")
                                    ageDays = $dateDiff.days
                                    mail = $_
                                }) | Out-Null
                            }
                        }# FIN BOUCLE de parcours des mails
                    }

                }
                else # On n'est pas en mode "notification"
                {
                    $logHistory.addLineAndDisplay(("-> VM '{0}' has snapshot since {1} ({2} days)" -f $vm.name, $createDate.toString("dd.MM.yyyy HH:mm:ss"), $dateDiff.days))

                    # Ajout au tableau pour un affichage propre à la fin
                    $vmWithSnap.add([PSCustomObject]@{
                        bgName = $project.name
                        VM = $vm.name
                        snapshotDate = $createDate.toString("dd.MM.yyyy HH:mm:ss")
                        ageDays = $dateDiff.days
                    }) | Out-Null
                }

            }# FIN BOUCLE de parcours des snap de la VM

        }# FIN BOUCLE de parcours de VM du BG

    }# FIN BOUCLE de parcours des BG


    # Si on doit envoyer des notifications
    if($sendNotifMail)
    {

        $logHistory.addLineAndDisplay("Sending notification mails...")

        # Parcours des adresses mail de notification pour les VMs qui on des "vieux" snapshots. Cela permet d'envoyer
        # un seul mail par personne, avec la liste des VM
        ForEach($mailTo in ($vmWithSnap | Select-Object -ExpandProperty mail | Sort-Object | Get-Unique))
        {
            $logHistory.addLineAndDisplay(("-> Processing mail '{0}'..." -f $mailTo))
            
            # Formatage des VM avec les snaps
            $detailList = $vmWithSnap | Where-Object { $_.mail -eq $mailTo } | ForEach-Object { 
                "<td>{0}</td><td>{1}</td><td>{2}</td><td>{3} days</td>" -f $_.VM, $_.bgName, $_.snapshotDate, $_.ageDays
            }

            $logHistory.addLineAndDisplay(("-> {0} VM associated to mail '{1}'..." -f $detailList.count, $mailTo))

            # Détails du mail
            $mailMessage = $mailMessageTemplate -f ($detailList -join "</tr>`n<tr>")

            # Envoi du mail
            $logHistory.addLineAndDisplay(("-> Sending mail to {0}..." -f $mailTo))

            Send-MailMessage -From $mailFrom -to $mailTo -Subject $mailSubject  `
                            -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding:UTF8 -ErrorVariable 'errorVar'

            # Si l'adresse mail n'existe pas
            if($errorVar.count -gt 0 -and $errorVar[0].Exception.Message -like "*Mailbox unavailable*")
            {
                $notifications.unknownMailboxes += ("<b>Mail: </b>{0}<br><b>VMs: </b> {1}" -f $mailTo, ( ($vmWithSnap | Where-Object { $_.mail -eq $mailTo } | ForEach-Object{ $_.VM }) -join ", "))
            }
            
            # Pour ne pas faire de spam
            Start-Sleep -Milliseconds 500
            
        }# FIN BOUCLE de parcours des noms de BG
    }
    else
    {
        # Affichage du résultat
        $vmWithSnap
    }

    # Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant

    $logHistory.addLineAndDisplay("Script execution done")
}
catch
{
    
    # Récupération des infos
    $errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace

    $logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
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
