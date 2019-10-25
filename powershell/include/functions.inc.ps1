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
	BUT : Renvoie la valeur d'une "Custom Property" donnée pour le Business Group passé

	IN  : $bg				-> Objet représentant le Business Group
	IN  : $customPropName	-> Nom de la Custom property à chercher
	
	RET : Valeur de la custom property
			$null si pas trouvé
#>
function getBGCustomPropValue([object]$bg, [string]$customPropName)
{
	# Recherche de la valeur de la "Custom Property" en PowerShell "optmisé"
	return (($bg.ExtensionData.entries | Where-Object {$_.key -eq $customPropName}).value.values.entries | Where-Object {$_.key -eq "value"}).value.value

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
function getBGWithCustomProp([Object] $fromList, [string] $customPropName, [string] $customPropValue )
{
	# Recherche dans la liste en utilisant la puissance de PowerShell
	return $fromList | Where-Object {(getBGCustomPropValue -bg $_ -customPropName $customPropName) -eq $customPropValue }
}


<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie le nom du cluster défini dans une Reservation

	IN  : $reservation	-> Objet contenant la réservation.
#>
function getResClusterName([PSObject]$reservation)
{
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
function sendMailTo([string]$mailAddress, [string] $mailSubject, [string] $mailMessage)
{
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
function ADGroupExists([string]$groupName)
{
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
function getvRAMailSubject([string] $shortSubject, [string]$targetEnv, [string]$targetTenant)
{

	return "vRA Service [{0}->{1}]: {2}" -f $targetEnv, $targetTenant, $shortSubject
}


<#
-------------------------------------------------------------------------------------
	BUT : Crée un contenu de mail en ajoutant le début et la fin.

	IN  : $content -> contenu du mail initial
#>
function getvRAMailContent([string] $content)
{

	return "Bonjour,<br><br>{0}<br><br>Salutations,<br>L'équipe vRA.<br> Paix et prospérité \\//" -f $content
}


<#
-------------------------------------------------------------------------------------
	BUT : Retourne le hash de la chaîne de caractères passée 

	IN  : $string	-> Chaine de caractères depuis laquelle créer le hash
	IN  : $hashName	-> Nom de la fonction de hash à utiliser:
						- MD5
						- RIPEMD160
						- SHA1
						- SHA256
						- SHA384
						- SHA512
#>
function getStringHash([String] $string, $hashName = "MD5") 
{ 
	$stringBuilder = New-Object System.Text.StringBuilder 
	[System.Security.Cryptography.HashAlgorithm]::Create($hashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($string))| ForEach-Object{ 
		[Void]$stringBuilder.Append($_.ToString("x2")) 
	} 
	return $stringBuilder.ToString() 
}


<#
-------------------------------------------------------------------------------------
	BUT : Retourne le timestamp unix actuel
#>
function getUnixTimestamp()
{
	return [int][double]::Parse((Get-Date -UFormat %s))
}


<#
-------------------------------------------------------------------------------------
	BUT : Formate le dictionnaire passé en une une chaîne de caractère HTML

	IN  : $parameters	-> dictionnaire avec les paramètres.
#>
function formatParameters($parameters)
{
	$s = ""
	Foreach($param in $parameters.Keys)
	{
		$s = "{0}<br>{1}: {2}" -f $s, $param, $parameters[$param]
	}

	return $s
}

<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie la valeur d'une "Custom Property" donnée pour la VM passée

	IN  : $vm				-> Objet représentant le Business Group
	IN  : $customPropName	-> Nom de la Custom property à chercher
	
	RET : Valeur de la custom property
			$null si pas trouvé
#>
function getVMCustomPropValue([object]$vm, [string]$customPropName)
{
	# Recherche de la valeur de la "Custom Property" en PowerShell "optmisé"
	return ($vm.resourceData.entries | Where-Object {$_.key -eq $customPropName}).value.value 
}

<#
	-------------------------------------------------------------------------------------
	BUT : Tronque une chaîne de caractères à une taille définie

	IN  : $str			-> la chaîne à tronquer
	IN  : $maxChar		-> Le nombre de caractères max autorisés
#>
function truncateString([string]$str, [int]$maxChars)
{
	return $str.subString(0, [System.Math]::Min($maxChars, $str.Length)) 
}