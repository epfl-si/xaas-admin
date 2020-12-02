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
    hidden [string]$logFolderPath
	hidden [string]$logFilename

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet et créé le dossier de logs si besoin (dans $rootFolderPath).
              Le dossier créé portera le nom $logName et c'est dans celui-ci qu'on créera les fichiers logs,
              un par jour.

        IN  : $logName          -> Nom du log
        IN  : $rootFolderPath   -> Chemin jusqu'au dossier racine où mettre les logs.
        IN  : $nbDaysToKeep     -> Le nombre jours de profondeur que l'on veut garder
	#>
	LogHistory([string]$logName, [string]$rootFolderPath, [int]$nbDaysToKeep)
	{
        # On créé un dossier avec la date du jour pour le log
        $this.logFolderPath = [IO.Path]::Combine($rootFolderPath, $logName, (Get-Date -format "yyyy-MM-dd"))
        $this.logFilename = ("{0}.log" -f (Get-Date -Format "HH-mm-ss.fff"))

        # Si le dossier pour les logs n'existe pas encore,
        if(!(test-path $this.logFolderPath))
        {
            New-Item -ItemType Directory -Force -Path $this.logFolderPath | Out-null
        }
        else # Le dossier pour les logs existe déjà
        {
            # Suppression des "vieux logs"
            Get-ChildItem $this.logFolderPath | `
                Where-Object {$_.CreationTime -le (Get-Date).AddDays(-$nbDaysToKeep) } | Remove-Item -Force
        }

    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log

        IN  : $line -> La ligne à ajouter
	#>
    [void] addLine([string]$line)
    {
        ("{0}: {1}" -f (Get-Date -format "yyyy-MM-dd HH:mm:ss"), $line) | `
            Out-File -FilePath (Join-Path $this.logFolderPath $this.logFilename) -Append:$true 
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