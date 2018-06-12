<#
   BUT : Contient une classe permetant de gérer des logs pour un script donné.

   AUTEUR : Lucien Chaboudez
   DATE   : Avril 2018

   ----------
   HISTORIQUE DES VERSIONS
   10.04.2018 - 1.0 - Version de base
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
        $this.logFolderPath = (Join-Path $rootFolderPath $logName)
        $this.logFilename = ("{0}.log" -f (Get-Date -format "yyyy-MM-dd"))

        # Si le dossier pour les logs n'existe pas encore,
        if(!(test-path $this.logFolderPath))
        {
            New-Item -ItemType Directory -Force -Path $this.logFolderPath
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
    hidden [void] addLine([string]$line)
    {
        ("{0}: {1}" -f (Get-Date -format "yyyy-MM-dd HH:mm:ss"), $line) | `
            Out-File -FilePath (Join-Path $this.logFolderPath $this.logFilename) -Append:$true 
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute une ligne au fichier Log et l'affiche aussi dans la console

        IN  : $line -> La ligne à ajouter (et à afficher)
	#>
	[void] addLineAndDisplay([string]$line)
	{
        Write-host $line
        $this.addLine($line)
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
}