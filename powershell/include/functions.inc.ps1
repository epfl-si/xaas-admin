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
	BUT : Permet de savoir si le Business Group passé est du type donné

	IN  : $bg		-> Business Group dont on veut savoir s'il est du type donné
	IN  : $type		-> Type duquel le BG doit être

	RET : $true|$false
			$null si custom property pas trouvée
#>
function isBGOfType
{
	param([PSCustomObject]$bg, [Array] $typeList)

	$bgType = getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_TYPE

	# Si custom property PAS trouvée,
	if($null -eq $bgType)
	{
		return $null
	}
	else # Custom property trouvée
	{
		# On regarde si la valeur est dans la liste
		return $typeList -contains $bgType
	}


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
	BUT : Renvoie la valeur d'une "Custom Property" donnée pour un objet vRA passé

	IN  : $object			-> Objet représentant l'élément dans lequel chercher la custom prop
	IN  : $customPropName	-> Nom de la Custom property à chercher
	
	RET : Valeur de la custom property
			$null si pas trouvé
#>
function getvRAObjectCustomPropValue([PSObject]$object, [string]$customPropName)
{
	# Recherche de la valeur de la "Custom Property" en PowerShell "optmisé"
	return ($object.resourceData.entries | Where-Object {$_.key -eq $customPropName}).value.value 
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

	IN  : $source				-> String avec le code HTML à convertir en PDF.
	IN  : $destinationFileFile	-> Localisation du fichier PDF de sortie
	IN  : $binFolder				-> Chemin jusqu'au dossier où se trouvent les DLL utilisées 
									la fonction:
									+ itextsharp.dll
									+ itextshar.xmlworker.dll
	IN  : $author				-> Nom de l'auteur à mettre dans le fichier PDF
	IN  : $landscape			-> $true|$false pour dire si orientation paysage

	REMARQUE : les tags HTML suivants ne sont pas supportés:
				<br>  (il faut utiliser des <p> mettre des <p>&nbsp;</p> si on veut une ligne vide)
	
	Un peu de documentation ici: https://github.com/itext/itextsharp/blob/develop/src/core/iTextSharp/text/Document.cs
#>
function convertHTMLtoPDF([string] $source, [string]$destinationFile, [string] $binFolder, [string] $author, [bool]$landscape)
{	
	
	# Chargement des DLL
	try
	{
		Add-Type -Path ([IO.Path]::combine($binFolder, 'itextsharp.dll')) -ErrorAction 'Stop'
	}
	catch
	{
		Throw 'Error loading the iTextSharp Assembly'
	}
			
	try
	{
		Add-Type -Path ([IO.Path]::Combine($binFolder, 'itextsharp.xmlworker.dll')) -ErrorAction 'Stop'	
	}		
	catch
	{	
		Throw 'Error loading the XMLWorker Assembly'
	}

	# Création du document PDF "logique"
	$pdfDocument = New-Object iTextSharp.text.Document
	
	# Doc sur PageSize: https://github.com/itext/itextsharp/blob/develop/src/core/iTextSharp/text/PageSize.cs
	if($landscape)
	{
		$pageSize = [iTextSharp.text.PageSize]::A4.Rotate()
	}
	else
	{
		$pageSize = [iTextSharp.text.PageSize]::A4
	}
	$pdfDocument.SetPageSize($pageSize) | Out-Null

	# Création du lecteur de fichier 
	$reader = New-Object System.IO.StringReader($source)
	
	# Pour écrire le fichier PDF
	$stream = [IO.File]::OpenWrite($destinationFile)
	$writer = [itextsharp.text.pdf.PdfWriter]::GetInstance($pdfDocument, $stream)
	
	# Defining the Initial Lead of the Document, BUGFix
	$writer.InitialLeading = '12.5'
	
	# Ouverture du document pour y importer le HTML
	$pdfDocument.Open()

	# Ajout de l'auteur. Ceci ne peut être fait qu'à partir du moment où le document PDF a été ouvert (via 'Open() )
	$pdfDocument.AddAuthor($author) | Out-Null
	
	
	# On tente de charger le HTML dans le document PDF 
	[iTextSharp.tool.xml.XMLWorkerHelper]::GetInstance().ParseXHtml($writer, $pdfDocument, $reader)
	
	# Fermeture du PDF + nettoyage
	$pdfDocument.close()
	$pdfDocument.Dispose()
	
}


<#
	-------------------------------------------------------------------------------------
	BUT : Tronque un nombre à virgule pour avoir un nombre décimales définies (sans arrondir)

	IN  : $number		-> Le nombre à tronquer
	IN  : $nbDecimals	-> Le nombre de décimales à mettre
#>
function truncateToNbDecimal([float]$number, [int]$nbDecimals)
{
	return [System.Math]::Floor($number * [Math]::Pow(10, $nbDecimals)) / [Math]::Pow(10, $nbDecimals)
}


<#
    -------------------------------------------------------------------------------------
    BUT : Enregistre une erreur d'appel REST dans un dossier avec quelques fichiers
    
    IN  : $category     -> Catégorie de l'erreur
    IN  : $errorId      -> ID de l'erreur
    IN  : $errorMsg     -> Message d'erreur
    IN  : $jsonContent  -> Contenu du fichier JSON

    RET : Chemin jusqu'au dossier où seront les informations de l'erreur
#>
function saveRESTError([string]$category, [string]$errorId, [string]$errorMsg, [PSObject]$jsonContent)
{
    $errorFolder =  ([IO.Path]::Combine($global:ERROR_FOLDER, $category, $errorId))

    New-Item -ItemType "directory" -Path $errorFolder | Out-Null

    $jsonContent | Out-File ([IO.Path]::Combine($errorFolder, "REST.json"))

    $errorMsg | Out-File ([IO.Path]::Combine($errorFolder, "error.txt"))

    return $errorFolder

}


<#
    -------------------------------------------------------------------------------------
    BUT : Permet de savoir si un objet contient une propriété d'un nom donné.
    
    IN  : $obj     		-> L'objet concerné
    IN  : $propertyName -> Nom de la propriété que l'on cherche

    RET : $true ou $false
#>
function objectPropertyExists([PSCustomObject]$obj, [string]$propertyName)
{
	return ((($obj).PSobject.Properties | Select-Object -ExpandProperty "Name") -contains $propertyName)
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie le type d'entité de facturation en fonction du tenant
    
    IN  : $tenant   -> Nom du tenant

    RET : Type d'entité, type [BillingEntityType]. Défini dans le fichier include/define.inc.ps1
#>
function getBillingEntityTypeFromTenant([string]$tenant)
{
    switch($tenant)
    {
        $global:VRA_TENANT__EPFL { return [BillingEntityType]::Unit }
        $global:VRA_TENANT__ITSERVICES { return [BillingEntityType]::Service }
        $global:VRA_TENANT__RESEARCH { return [BillingEntityType]::Project }
    }
}


<#
    -------------------------------------------------------------------------------------
	BUT : Charge le contenu d'un fichier JSON qui peut contenir des commentaires.
			// commentaire sur une ligne
			/* commentaire
			sur plusieurs lignes */

			Les commentaires sont simplement supprimés au chargement du fichier.
    
    IN  : $jsonFile		-> Chemin jusqu'au fichier JSON à charger

    RET : Objet représentant le contenu du fichier JSON
#>
function loadFromCommentedJSON([string]$jsonFile)
{
	return ((Get-Content -Path $jsonFile -raw -Encoding:UTF8) -replace '(?m)\s*//.*?$' -replace '(?ms)/\*.*?\*/') | ConvertFrom-JSON
}