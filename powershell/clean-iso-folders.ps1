<#
USAGES:
	clean-iso-folders.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl
#>
<#
    BUT 		: Fait du nettoyage dans les dossiers où se trouvent les ISO privées des différents
                  Business Groups.

	DATE 		: Février 2019
	AUTEUR 	    : Lucien Chaboudez

	Prérequis:
	-
	
    
	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>
param ( [string]$targetEnv, [string]$targetTenant)


. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configVSphere = [ConfigReader]::New("config-vsphere.json")
$configGlobal = [ConfigReader]::New("config-global.json")




# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logHistory =[LogHistory]::new('0.Clean-ISO-Folders', (Join-Path $PSScriptRoot "logs"), 30)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))


	$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}, Tenant={1}" -f $targetEnv, $targetTenant))

	$logHistory.addLineAndDisplay(("Looking for ISO files older than {0} days" -f $global:PRIVATE_ISO_LIFETIME_DAYS))


	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()
	$counters.add('ISOFound', '# "old" ISO files found')
	$counters.add('ISODeleted', '# ISO files deleted')
	$counters.add('ISOUnmounted', '# ISO files unmounted to be deleted')


    # On n'ouvre pas de connexion à vRA tout de suite car si ça se trouve, il n'y a rien à supprimer donc ouvrir une connexion pour rien serait... inutile
    # (je me demande, est-ce quelqu'un d'autre que moi va lire ce commentaire un jour?...)
	$vra = $null
	$vCenter = $null

    # Récupération du dossier racine où se trouvent les ISO, histoire de pouvoir le parcourir
	$rootISOFolder = $nameGenerator.getNASPrivateISORootPath()
	
	$logHistory.addLineAndDisplay(("Looking for ISO files in {0}..." -f $rootISOFolder))

    # Recherche des fichiers ISO qui ont été créés il y a plus de $global:PRIVATE_ISO_LIFETIME_DAYS jours
    ForEach($isoFile in (Get-ChildItem -Path $rootISOFolder -Recurse -Filter "*.iso" | Where-Object {$_.CreationTime -lt (Get-Date).addDays(-$global:PRIVATE_ISO_LIFETIME_DAYS)}))
    {
		# Recherche du nom du BG auquel l'ISO est associée 
		$bgName = $nameGenerator.getNASPrivateISOPathBGName($isoFile.FullName)
		
		$logHistory.addLineAndDisplay(("ISO file found! ${0} - BG:${1}" -f $isoFile.FullName, $bgName))
		$counters.inc('ISOFound')

		# Si on n'a pas encore de connexion à vRA, là, ça serait bien d'en ouvrir une histoire pouvoir continuer.
		if($null -eq $vra)
		{
			$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "server"), 
								$targetTenant, 
								$configVra.getConfigValue($targetEnv, $targetTenant, "user"), 
								$configVra.getConfigValue($targetEnv, $targetTenant, "password"))
		}	

		# Si on n'a pas encore de connexin à vCenter, c'est aussi maintenant qu'on va l'établir. Enfin, on pourrait faire ça plus tard dans le code mais vu qu'on vient
		# de faire la connexion à vRA, ça paraît logique de faire vCenter ici aussi.
		if($null -eq $vCenter)
		{
			# Chargement des modules 
			loadPowerCliModules

			# Pour éviter que le script parte en erreur si le certificat vCenter ne correspond pas au nom DNS primaire. On met le résultat dans une variable
			# bidon sinon c'est affiché à l'écran.
			$dummy = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

			$credSecurePwd = $configVSphere.getConfigValue($targetEnv, "password") | ConvertTo-SecureString -AsPlainText -Force
			$credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $configVSphere.getConfigValue($targetEnv, "user"), $credSecurePwd	

			$vCenter = Connect-VIServer -Server $configVSphere.getConfigValue($targetEnv, "server") -Credential $credObject
		}
		
		# Recherche des infos du BG
		$bg = $vra.getBG($bgName)

		# Si on trouve un BG, on regarde si celui-ci contient des VM et si l'un d'eux pourrait monter l'ISO. 
		# A noter que si le BG n'existe pas, bah, y'a pas de VM dedans et aucune ne peux monter une ISO, forcément... donc on peut l'effacer.
		if($null -ne $bg)
		{
			# Recherche de la liste des VM existantes dans le Tenant
			$vmList = $vra.getBGItemList($bg, 'Virtual Machine')

			# Parcours des VM
			ForEach($vm in $vmList)
			{
				$logHistory.addLineAndDisplay(("Checking VM '${0}'..." -f $vm.name))

				# On recherche une éventuelle ISO montée 
				$mountedISO = (Get-VM -Name $vm.name | Get-CDDrive).IsoPath

				# Si c'est différent de $null, ça ne veut pas encore dire qu'il y a une ISO de montée
				if($null -ne $mountedISO)
				{
					# Les infos de l'ISO ont l'aspect suivant :
					# [<datastore>] path/to/image.iso
					# Mais ça peut aussi avoir l'aspect :
					# [] (path vide)
					# Dans ce dernier cas, c'est comme si aucune ISO n'était montée.
					
					# On commencer par virer le nom du datastore (même s'il est vide) et on dit merci aux expressions régulières
					$mountedISO = ($mountedISO -replace "\[.*\]\s", "").Trim()

					# On regarde maintenant si le chemin jusqu'à l'ISO que l'on a trouvée sur le volume se termine par celui de l'ISO montée
					# Si c'est le cas, c'est que l'ISO est utilisée donc on ne peut pas l'effacer 
					if($mountedISO -ne "" -and $isoFile.FullName.endsWith($mountedISO))
					{
						# on démonte l'image en mettant "no-media" 
						Get-VM -Name $vm.name | Get-CDDrive | Set-CDDrive -NoMedia -Confirm:$false

						$logHistory.addLineAndDisplay("ISO file is mounted in VM. Unmounting...")
						$counters.inc('ISOUnmounted')
					}
					
				}

			}# FIN BOUCLE de parcours des VM du Business Group

		} 
		else # Le BG n'existe pas 
		{
			$logHistory.addLineAndDisplay(("Business Group not found in vRA '${0}'" -f $bgName))
		}
		
		# Quand on arrive ici, on assure que l'ISO n'est plus utilisée par aucune VM si c'était le cas auparavant avant.
		# On peut donc la faire disparaître

		Remove-Item $isoFile.FullName -Force
		$logHistory.addLineAndDisplay(("ISO file deleted: ${0}" -f $isoFile.FullName))
		$counters.inc('ISODeleted')
		

	} # FIN boucle de recherche des fichier ISO

    # Si on avait effectivement ouvert une connexion à vRA, on la referme 
    if($null -ne $vra)
    {
        $vra.disconnect()
	}
	# Si on avait ouvert une connexion à vCenter, on la referme 
	if($null -ne $vcenter)
	{
		Disconnect-VIServer -Server $vCenter -Confirm:$false 
	}

	# Affichage des compteurs
	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))
        
}
catch # Dans le cas d'une erreur dans le script
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

	$logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
	
	# On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
	$errorMessage = $errorMessage -replace "`n", "<br>"
	
	# Envoi d'un message d'erreur aux admins 
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant $targetTenant
	$mailMessage = getvRAMailContent -content ("<b>Computer:</b> {3}<br><b>Script:</b> {0}<br><b>Parameters:</b>{4}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Net.WebUtility]::HtmlEncode($errorTrace), $env:computername, (formatParameters -parameters $PsBoundParameters ))

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $mailMessage
	
}
