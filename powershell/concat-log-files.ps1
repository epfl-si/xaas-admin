<#
USAGES:
	concat-log-files.ps1 
#>
<#
	BUT 		: Regroupe les logs d'exécution (un fichier par exécution) des jours passés dans le même fichier log

	DATE 		: Novembre 2018
	AUTEUR 	: Lucien Chaboudez

	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>

$rootLogFolder = (Join-Path $PSScriptRoot "logs")
$today = (Get-Date -format "yyyy-MM-dd")

# Parcours des dossiers log de chaque script
Get-ChildItem -Path $rootLogFolder -Recurse:$false -Directory | ForEach-Object {

    Write-Host ("Processing {0}..." -f $_.Name)
    $scriptFolder = $_.FullName

    # Parcours des dossiers pour le log du script courant. Il y a normalement un dossier par jour
    Get-ChildItem -Path $_.FullName -Recurse:$false -Directory | ForEach-Object {

        Write-Host ("-> Processing date folder {0}..." -f $_.Name)

        # Si c'est le dossier du jour courant, on le skip car il pourrait encore y avoir d'autres fichiers logs d'ajoutés dedans.
        if($_.Name -eq $today)
        {
            Write-Host "-> Current day folder, skipping!"
            return
        }

        # Définition du nom du fichier dans lequel on va regrouper les logs
        $mergeLogFile = (Join-path $scriptFolder ("{0}.log" -f $_.Name))
        
        # Si le fichier dans lequel on veut regrouper n'existe pas,
        if(!(Test-Path -Path $mergeLogFile))
        {
            New-Item -ItemType File -Path $mergeLogFile | Out-Null
        }

        # Parcours des fichiers qui sont dans le dossier (ils sont parcourus par ordre alphabétique )
        Get-ChildItem -Path $_.FullName -Recurse:$false -File | ForEach-Object {
            Write-Host ("--> Processing log file {0}..." -f $_.Name)

            # Ajout du contenu du fichier LOG courant dans le "global"
            Get-Content -Path $_.FullName | Add-Content -Path $mergeLogFile
            
            Write-Host ("--> Removing log file {0}..." -f $_.Name)
            # Suppression du fichier log courant
            Remove-Item $_.FullName -Force

        } # FIN BOUCLE de parcours des fichiers LOG pour une date donnée 

        Write-Host ("-> Removing date folder {0}..." -f $_.Name)
        # on peut maintenant supprimer le dossier de la date
        Remove-Item $_.FullName -Force

    } # FIN BOUCLE de parcours des dossiers avec les dates d'exécution


}
Write-Host "All folder/files processed, see you tomorrow for next merge!"