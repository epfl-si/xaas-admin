<#
   BUT : Contient juste une méthode, celle permettant de charger des informations depuis
        des fichiers JSON pour ensuite être utilisés dans des appels à une API quelconque, 
        que cela soit via REST ou via des méthodes PowerShell (cmdlet)

   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2019

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class APIUtils
{

    <#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
	#>
    APIUtils()
    {

    }

	<#
		-------------------------------------------------------------------------------------
		BUT : Charge un fichier JSON et renvoie le code.
				Le fichier doit se trouver dans le dossier spécifié par $global:JSON_TEMPLATE_FOLDER

		IN  : $file				-> Fichier JSON à charger
		IN  : $valToReplace	-> (optionnel) Dictionnaaire avec en clef la chaine de caractères
										à remplacer dans le code JSON (qui sera mise entre {{ et }} dans
										le fichier JSON). 
										En valeur, on peut trouver :
										- Chaîne de caractères à mettre à la place de la clef
										- Tableau avec:
											[0] -> Chaîne de caractères à mettre à la place de la clef
											[1] -> $true|$false pour dire s'il faut remplacer aussi ou pas
													les "" qui entourent la clef qui est entre {{ }}.
													On est en effet obligés de mettre "" autour sinon on
													pète l'intégrité du JSON.

		RET : Objet créé depuis le code JSON
	#>
	hidden [Object] loadJSON([string] $file, [System.Collections.IDictionary] $valToReplace)
	{
		# Chemin complet jusqu'au fichier à charger
		$filepath = (Join-Path $global:JSON_TEMPLATE_FOLDER $file)

		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("JSON file not found ({0})" -f $filepath)
		}

		# Chargement du code JSON
		$json = (Get-Content -Path $filepath) -join "`n"

		# S'il y a des valeurs à remplacer
		if($null -ne $valToReplace)
		{
			# Parcours des remplacements à faire
			foreach($search in $valToReplace.Keys)
			{
				# Si on a des infos pour savoir si on doit supprimer ou pas les doubles quotes 
				if($valToReplace.Item($search) -is [Array])
				{
					# Extraction des informations 
					$replaceWith, $removeDoubleQuotes = $valToReplace.Item($search)	
				}
				else # On a juste la chaîne de caractères 
				{
					$replaceWith = $valToReplace.Item($search)
					$removeDoubleQuotes = $false
				}

				$search = "{{$($search)}}"
				
				# Si on doit supprimer les doubles quotes autour de {{ }}
				if($removeDoubleQuotes)
				{
					# Ajout des doubles quotes pour la recherche
					$search = "`"$($search)`""
				}

				# Recherche et remplacement de l'élément
				$json = $json -replace $search, $replaceWith
			}
		}
		try
		{
			return $json | ConvertFrom-Json
		}
		catch
		{
			Throw ("Error converting JSON from file ({0})" -f $filepath)
		}
	}
    
}