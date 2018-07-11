<#
   BUT : Contient les fonctions utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   15.02.2018 - 1.0 - Version de base
   08.03.2018 - 1.1 - Ajout de sendMailTo
   07.06.2018 - 1.2 - Ajout getvRAMailSubject, getvRAMailContent, ADGroupExists

#>

<#
	-------------------------------------------------------------------------------------
	BUT : Permet de dire si un nom d'environnement est correct ou pas

	IN  : $targetEnv -> Nom de l'environnement à contrôler

	RET : $true|$false
#>
function targetEnvOK
{
	param([string] $targetEnv)
	return $global:TARGET_ENV_LIST -contains $targetEnv
}

<#
	-------------------------------------------------------------------------------------
	BUT : Permet de dire si un nom de Tenant est correct ou pas

	IN  : $targetEnv -> Nom du Tenant à contrôler

	RET : $true|$false
#>
function targetTenantOK
{
	param([string] $targetTenant)
	return $global:TARGET_TENANT_LIST -ccontains $targetTenant
}

<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie l'adresse mail des managers d'une faculté donnée

	IN  : $faculty -> La faculté

	RET : Adresse mail
#>
function getManagerEmail
{
	param([string] $faculty)

	Write-Warning "!!!! getManagerEmail !!!! --> TODO"

	return "facadm-{0}@epfl.ch" -f $faculty
}


<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie le Business Group qui a une "Custom Property" avec une valeur donnée, 
		  ceci à partir d'une liste de Business Group

	IN  : $fromList			-> Liste de BG dans laquelle chercher
	IN  : $customPropName	-> Nom de la Custom property à chercher
	IN  : $customPropValue	-> Valeur que la custom property doit avoir

	RET : PSObject contenant le BG
			$null si pas trouvé
#>
function getBGWithCustomProp
{
	param([Object] $fromList, [string] $customPropName, [string] $customPropValue )

	# Parcours des BG existants
	foreach($bg in $fromList)
	{
		# Parcours des entrées des ExtensionData
		foreach($entry in $bg.ExtensionData.entries)
		{
			# Si on trouve l'entrée avec le nom que l'on cherche,
			if($entry.key -eq $customPropName)
			{
				# Parcours des informations de cette entrée
				foreach($entryVal in $entry.value.values.entries)
				{
					if($entryVal.key -eq "value" -and $entryVal.value.value -eq $customPropValue)
					{
						return $bg
					}
				}
			}
		}
	}
	return $null
}


<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie le nom du cluster défini dans une Reservation

	IN  : $reservation	-> Objet contenant la réservation.
#>
function getResClusterName
{
	param([PSObject]$reservation)

	return ($reservation.ExtensionData.entries | Where-Object {$_.key -eq "computeResource"} ).value.label

}


<#
	-------------------------------------------------------------------------------------
	BUT : Envoie un mail aux admins du service (NAS ou MyNAS vu que c'est la même adresse mail)
		  Afin de pouvoir envoyer un mail en UTF8 depuis un script PowerShell encodé en UTF8, il 
		  faut procéder d'une manière bizarre... il faut sauvegarder le contenu du mail à envoyer
		  dans un fichier, avec l'encoding "default" (ce qui fera un encoding UTF8, je cherche pas
		  pourquoi...) et ensuite relire le fichier en spécifiant le format UTF8 cette fois-ci...
		  Et là, abracadabra, plus de problème d'encodage lorsque l'on envoie le mail \o/

	IN  : $mailAddress	-> Adresse à laquelle envoyer le mail. C'est aussi cette adresse qui
									sera utilsée comme adresse d'expéditeur. Le nécessaire sera ajouté
									au début de l'adresse afin qu'elle puisse être utilisée comme
									adresse d'expédition sans que le système mail de l'école ne la
									refuse.
   IN  : $mailSubject   -> Le sujet du mail
   IN  : $mailMessage   -> Le contenu du message
#>
function sendMailTo
{
	param([string]$mailAddress, [string] $mailSubject, [string] $mailMessage)

	$tmpMailFile = ".\tmpmail.txt"

	$mailMessage | Out-File $tmpMailFile -Encoding default
	$mailMessage = Get-Content $tmpMailFile -Encoding UTF8 | Out-String
	Remove-Item $tmpMailFile

    Send-MailMessage -From "noreply+$mailAddress" -To $mailAddress -Subject $mailSubject -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding Unicode
}

<#
	-------------------------------------------------------------------------------------
	BUT : Permet de savoir si un groupe Active Directory existe.
	   
	IN  : $groupName	-> Le nom du groupe à contrôler.
#>
function ADGroupExists
{
	param([string]$groupName)

	try
	{
		# On tente de récupérer le groupe (on met dans une variable juste pour que ça ne s'affiche pas à l'écran)
		$adGroup = Get-ADGroup -Identity $groupName
		# Si on a pu le récupérer, c'est qu'il existe.
		return $true

	}
	catch # Une erreur est survenue donc le groupe n'existe pas
	{
		return $false
	}
}



<#
-------------------------------------------------------------------------------------
	BUT : Crée un sujet de mail pour vRA à partir du sujet "court" passé en paramètre
		  et du nom de l'environnement courant

	IN  : $shortSubject -> sujet court
	IN  : $targetEnv	-> Environnement courant
	IN  : $targetTenant -> Tenant courant
#>
function getvRAMailSubject
{
	param([string] $shortSubject, [string]$targetEnv)

	return "vRA Service [{0}->{1}]: {2}" -f $targetEnv, $targetTenant, $shortSubject
}


<#
-------------------------------------------------------------------------------------
	BUT : Crée un contenu de mail en ajoutant le début et la fin.

	IN  : $content -> contenu du mail initial
#>
function getvRAMailContent
{
	param([string] $content)

	return "Bonjour,<br><br>{0}<br><br>Salutations,<br>L'équipe vRA.<br> Paix et prospérité \\//" -f $content
}


<#
-------------------------------------------------------------------------------------
	BUT : Tente de charger un fichier de configuration. Si c'est impossible, une 
		  erreur est affichée et on quitte.

	IN  : $filename	-> chemin jusqu'au fichier à charger.
#>
function loadConfigFile([string]$filename)
{
	try 
	{
		. $filename
	}
	catch 
	{
		Write-Error ("Config file not found ! ({0})`nPlease create it from 'sample' file" -f $filename)
		exit
	}
}