<#
   BUT : Contient une classe permetant de gérer des logs pour un script donné.
        On fait en sorte de créer un fichiers LOG différent à chaque appel du script. 
        Les fichiers sont regroupés dans un dossier avec la date d'exécution.

   AUTEUR : Lucien Chaboudez
   DATE   : Avril 2018

   ----------
   HISTORIQUE DES VERSIONS
   10.04.2018 - 1.0 - Version de base
   25.11.2019 - 1.1 - Création d'un dossier par jour avec les fichiers logs
#>
class LogHistory
{
    hidden [string]$allLogsFolder
    hidden [string]$logTodayFolderPath
	hidden [string]$logTodayFilename

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet et créé le dossier de logs si besoin (dans $rootFolderPath).
              Le dossier créé portera le nom $logName et c'est dans celui-ci qu'on créera les fichiers logs,
              un par jour.

        IN  : $logPath          -> Tableau avec le "chemin" jusqu'au log
        IN  : $rootFolderPath   -> Chemin jusqu'au dossier racine où mettre les logs.
        IN  : $nbDaysToKeep     -> Le nombre jours de profondeur que l'on veut garder
	#>
	LogHistory([Array]$logPath, [string]$rootFolderPath, [int]$nbDaysToKeep)
	{
        # Dossier pour tous les fichiers du log
        $this.allLogsFolder = ""
        $cmd = '$this.allLogsFolder = [IO.Path]::Combine($rootFolderPath, "{0}")' -f ($logPath -join '","')
        Invoke-Expression $cmd

        # On créé un dossier avec la date du jour pour le log
        $this.logTodayFolderPath = [IO.Path]::Combine($this.allLogsFolder, (Get-Date -format "yyyy-MM-dd"))
        
        $this.logTodayFilename = ("{0}.log" -f (Get-Date -Format "HH-mm-ss.fff"))

        # Si le dossier pour les logs n'existe pas encore,
        if(!(test-path $this.logTodayFolderPath))
        {
            New-Item -ItemType Directory -Force -Path $this.logTodayFolderPath | Out-null
        }
        
        $this.concatLogFiles()

        # Suppression des "vieux logs"
        Get-ChildItem $this.allLogsFolder -Directory | `
            Where-Object {$_.CreationTime -le (Get-Date).AddDays(-$nbDaysToKeep) } | Remove-Item -Force -Recurse
        
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Concatène les "vieux" fichiers logs pour en faire un seul par jour.
	#>
    hidden [void] concatLogFiles()
    {

        $today = (Get-Date -format "yyyy-MM-dd")
    
        # Parcours des dossiers pour le log du script courant. Il y a normalement un dossier par jour
        # On skip le jour courant car il pourrait encore y avoir d'autres fichiers logs d'ajoutés dedans.
        Get-ChildItem -Path $this.allLogsFolder -Recurse:$false -Directory | Where-Object { $_.Name -ne $today } | ForEach-Object {
            
            # Définition du nom du fichier dans lequel on va regrouper les logs
            $mergeLogFile = (Join-path $this.allLogsFolder ("{0}.log" -f $_.Name))
            
            # Si le fichier dans lequel on veut regrouper n'existe pas, on le créé vide
            if(!(Test-Path -Path $mergeLogFile))
            {
                New-Item -ItemType File -Path $mergeLogFile | Out-Null
            }
    
            # Parcours des fichiers qui sont dans le dossier (ils sont parcourus par ordre alphabétique )
            Get-ChildItem -Path $_.FullName -Recurse:$false -File | ForEach-Object {
                
                # Ajout du contenu du fichier LOG courant dans le "global"
                Get-Content -Path $_.FullName | Add-Content -Path $mergeLogFile
                
                # Suppression du fichier log courant
                Remove-Item $_.FullName -Force
    
            } # FIN BOUCLE de parcours des fichiers LOG pour une date donnée 
    
            # on peut maintenant supprimer le dossier de la date
            Remove-Item $_.FullName -Force
    
        } # FIN BOUCLE de parcours des dossiers avec les dates d'exécution
    
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log

        IN  : $line -> La ligne à ajouter
	#>
    [void] addLine([string]$line)
    {
        ("{0}: {1}" -f (Get-Date -format "yyyy-MM-dd HH:mm:ss"), $line) | `
            Out-File -FilePath (Join-Path $this.logTodayFolderPath $this.logTodayFilename) -Append:$true 
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log et l'affiche aussi dans la console

        IN  : $line     -> La ligne à ajouter (et à afficher)
        IN  : $color    -> Couleur du texte 
        IN  : $bgColor  -> Couleur du fond du texte

        NOTE: pour les couleurs possibles, voir ici:
            https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-host?view=powershell-7
    #>
    [void] addLineAndDisplay([string]$line, [string]$color, [string]$bgColor)
    {
        Write-host $line -BackgroundColor $bgColor -ForegroundColor $color
        $this.addLine($line)
    }
	[void] addLineAndDisplay([string]$line)
	{
        Write-host $line
        $this.addLine($line)
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log

        IN  : $line -> La ligne à ajouter (et à afficher)
	#>
	[void] addError([string]$line)
	{
        $this.addLine(("!!ERROR!! {0}" -f $line))
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log et l'affiche aussi dans la console en mode ERREUR

        IN  : $line -> La ligne à ajouter (et à afficher)
	#>
	[void] addErrorAndDisplay([string]$line)
	{
        Write-Error $line
        $this.addLine(("!!ERROR!! {0}" -f $line))
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log et l'affiche aussi dans la console en mode WARNING

        IN  : $line -> La ligne à ajouter (et à afficher)
	#>
	[void] addWarningAndDisplay([string]$line)
	{
        Write-Warning $line
        $this.addLine(("!!WARNING!! {0}" -f $line))
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log pour dire que c'est du DEBUG

        IN  : $line -> La ligne à ajouter
	#>
	[void] addDebug([string]$line)
	{
        $this.addLine(("!!DEBUG!! {0}" -f $line))
    }
}