<#
   BUT : Contient une classe avec les fonctions de base pour faire des appels via la
            commande TKGI.exe
	
    PREREQUIS : Pour fonctionner, cette classe nécessite le binaire tkgi.exe, il doit
                se trouver dans le dossier "powershell/bin"
                Il faut aussi avoir un certificat pour la connexion
				

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

#>
class TKGI
{
	
	hidden [System.Diagnostics.Process]$batchFile
    hidden [PSObject]$process
    hidden [string]$server
    hidden [string]$loginCmd
    hidden [string]$logoutCmd
    hidden [string]$pathToTKGI
	
    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

        IN  : $server			-> Nom DNS du serveur
        IN  : $clientName       -> Nom du client à utiliser pour se connecter à l'API
                                    ATTENTION: ce n'est pas un utilisateur du domaine, c'est celui 
                                               défini dans le fichier de configuration de K8s
        IN  : $clientSecret     -> Secret pour se connecter avec le client name. Même remarque que
                                    pour $clientName 
        IN  : $certificateFile  -> Nom du fichier certificat à utiliser. Doit se
                                    trouver dans le dossier spécifié par
                                    $global:K8S_CERT_FOLDER
	#>
    TKGI([string] $server, [string]$clientName, [string]$clientSecret, [string]$certificateFile)
    {
        $this.server = $server
        $certificateFileFull = [IO.Path]::Combine($global:K8S_CERT_FOLDER, $certificateFile)

        # Check TKGI
		$this.pathToTKGI = [IO.Path]::Combine($global:BINARY_FOLDER, "tkgi.exe")
		# On check qu'on a bien le tout pour faire le job 
		if(!(Test-Path $this.pathToTKGI))
		{
			Throw ("Binary file 'tkgi.exe' is missing... (in folder {0})" -f $this.this.pathToTKGI)
        }
        if(!(Test-Path $certificateFileFull))
		{
			Throw ("Certificate file '{0}' is missing... (in folder {1})" -f $certificateFile, $global:K8S_CERT_FOLDER)
        }
        
        # Ligne pour se connecter à l'API
        $this.loginCmd = "{0} login -a https://{1} --client-name {2} --client-secret {3} --ca-cert {4}" -f $this.pathToTKGI, $server, $clientName, $clientSecret, $certificateFileFull
        $this.logoutCmd = "{0} logout" -f $this.pathToTKGI

		# Création du nécessaire pour exécuter un process CURL
		$this.batchFile = New-Object System.Diagnostics.Process
		# On est obligé de mettre UseShellExecute à true sinon ça foire avec le code de retour de
		# la fonction 
		$this.batchFile.StartInfo.UseShellExecute = $false

        $this.batchFile.StartInfo.RedirectStandardOutput = $true
        $this.batchFile.StartInfo.RedirectStandardError = $true

        $this.batchFile.StartInfo.CreateNoWindow = $false
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Exécute une liste de commandes

        IN  : $commandList      -> Tableau avec la liste des commandes à exécuter.
                                    Pas besoin de mettre "tkgi.exe" au début des commandes
        
        RET : Tableau associatif avec en clef la commande passée et en valeur, le résultat (string) de
                la commande
	#>
    [HashTable] exec([Array]$commandList)
    {
        $cmdFile = (New-TemporaryFile).FullName
        # On met une extension qui permettra de l'exécuter correctement par la suite via cmd.exe
        $batchFilePath = ("{0}.cmd" -f $cmdFile)
        Rename-Item -Path $cmdFile -NewName $batchFilePath

        $cmdResults = @{}

        # Création des lignes de commandes à exécuter
        $this.loginCmd | Out-File -FilePath $batchFilePath -Encoding:default
        $commandList | ForEach-Object{ 
            ("{0} {1}" -f $this.pathToTKGI, $_) | Out-File -FilePath $batchFilePath -Append -Encoding:default
        } 
        $this.logoutCmd | Out-File -FilePath $batchFilePath -Append -Encoding:default

        $this.batchFile.StartInfo.FileName = $batchFilePath

        $this.batchFile.Start() | Out-Null

        $output = $this.batchFile.StandardOutput.ReadToEnd()
        $errorStr = $this.batchFile.StandardError.ReadToEnd()

        # Suppression du fichier temporaire
        if(Test-Path $batchFilePath)
        {
            Remove-Item $batchFilePath 
        }

        # Si aucune erreur
        if($this.batchFile.ExitCode -eq 0)
        {
            # J'admets, cette ligne de commande, je l'ai trouvée sur le net, j'aurais jamais trouvé tout seul XD
            $separator = [string[]]@($this.pathToTKGI)

            # On explose les résultats des différentes commandes via le chemin jusqu'à "tkgi.exe" 
            # et on les parcoure
            $output.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {

                # Suppression de chemin jusqu'au dossier courant qui se trouve entre les commandes: 
                # Ex: PS D:\IDEVING\IaaS\git\xaas-admin\powershell>
                $cmdRes = ($_ -replace '(.*?)>', '').Trim()

                if($cmdRes -eq "")
                {
                    # Passage à l'itération suivante
                    return
                }
                # Extraction du nom de la commande passée
                $cmdName = ($cmdRes -split "`n")[0].Trim()

                # Si la commande faisait partie de ce qu'on devait exécuter
                if($commandList -contains $cmdName)
                {
                    # Ajout de la commande et de son résultat dans ce qu'on renvoie
                    $cmdResults.Add($cmdName, ($cmdRes -split $cmdName)[1].Trim())
                }
            }


        }
        else
        {
            Throw ("Error executing commands ({0}) with error : `n{1}" -f $this.batchFile.StartInfo.Arguments, $errorStr)
        }

        return $cmdResults
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Exécute une commande unique

        IN  : $command			-> La commande à exécuter
                                    Pas besoin de mettre "tkgi.exe" au début de la commande
        
        RET : Tableau associatif avec en clef la commande passée et en valeur, le résultat (string) de
                la commande
	#>
    [HashTable] exec([string]$command)
    {
        return $this.exec( @($command) )
    }

}