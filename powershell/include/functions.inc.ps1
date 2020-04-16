<#
   BUT : Contient les fonctions utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   15.02.2018 - 1.0 - Version de base
   08.03.2018 - 1.1 - Ajout de sendMailTo
   07.06.2018 - 1.2 - Ajout getvRAMailSubject, getvRAMailContent, ADGroupExists
   10.01.2020 - 1.3 - Suppression sendMailTo, getvRAMailSubject et getvRAMailContent car création d'une classe pour faire le job

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

	IN  : $vm				-> Objet représentant la VM
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


<#
	-------------------------------------------------------------------------------------
	BUT : Transforme du code HTML en un fichier PDF
			Le code de cette fonction a été repris ici (https://gallery.technet.microsoft.com/scriptcenter/Convertto-PDFFile-dda02118) 
			et a été simplifié

	IN  : $source				-> String avec le code HTML à convertir en PDF
	IN  : $destinationFileFile	-> Localisation du fichier PDF de sortie
	IN  : $binPath				-> Chemin jusqu'au dossier où se trouvent les DLL utilisées 
									la fonction:
									+ itextsharp.dll
									+ itextshar.xmlworker.dll
	IN  : $author				-> Nom de l'auteur à mettre dans le fichier PDF

	REMARQUE : les tags HTML suivants ne sont pas supportés:
				<br>  (il faut utiliser des <p> mettre des <p>&nbsp;</p> si on veut une ligne vide)
#>
function convertHTMLtoPDF([string] $Source, [string]$destinationFile, [string] $binPath, [string] $author )
{	
	
	# Chargement des DLL
	try
	{
		Add-Type -Path ([IO.Path]::combine($binPath, 'itextsharp.dll')) -ErrorAction 'Stop'
	}
	catch
	{
		Throw 'Error loading the iTextSharp Assembly'
	}
			
	try
	{
		Add-Type -Path ([IO.Path]::Combine($binPath, 'itextsharp.xmlworker.dll')) -ErrorAction 'Stop'	
	}		
	catch
	{	
		Throw 'Error loading the XMLWorker Assembly'
	}

	
	# Création du document PDF "logique"
	$pdfDocument = New-Object iTextSharp.text.Document
	$pdfDocument.SetPageSize([iTextSharp.text.PageSize]::A4) | Out-Null
	
	# Création du lecteur de fichier 
	$reader = New-Object System.IO.StringReader($Source)
	
	# Pour écrire le fichier PDF
	$stream = [IO.File]::OpenWrite($destinationFile)
	$writer = [itextsharp.text.pdf.PdfWriter]::GetInstance($pdfDocument, $stream)
	
	# Defining the Initial Lead of the Document, BUGFix
	$writer.InitialLeading = '12.5'
	
	# Ouverture du document pour y importer le HTML
	$pdfDocument.Open()

	# Ajout de l'auteur. Ceci ne peut être fait qu'à partir du moment où le document PDF a été ouvert (via 'Open() )
	$dummy = $pdfDocument.AddAuthor($author)
	
	# On tente de charger le HTML dans le document PDF 
	Try
	{	
		[iTextSharp.tool.xml.XMLWorkerHelper]::GetInstance().ParseXHtml($writer, $pdfDocument, $reader)
	}
	Catch [System.Exception]
	{
		Throw "Error parsing the HTML code"
		
	}

	# Fermeture du PDF + nettoyage
	$pdfDocument.close()
	$pdfDocument.Dispose()
	
}