<#
    BUT : Contient une classe avec les fonctions de base pour faire des appels via les commandes
            - tkgi.exe
            - kubectl.exe
    
    REMARQUE: Il est intéressant de savoir que les binaires en question utilisent la sortie STDERR 
                pour afficher des éléments informatifs tel que:
                - état du login
                - demande de mot de passe dans un prompt
                - message pour dire que pas de résultat pour ce qu'on a demandé
              Donc, c'est "naturellement" filtré entre STDOUT et STDERR au niveau de l'exécution
              du process et de la récupération de la sortie. C'est pratique mais un peu perturbant
              quand on n'est pas au courant de cette petite subtilité...
	
    PREREQUIS : Pour fonctionner, cette classe nécessite les binaires mentionnés plus haut, ils doivent
                se trouver dans le dossier "powershell/bin"
                Il faut aussi avoir un certificat pour la connexion
				

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

#>
class TKGIKubectl
{
	
	hidden [System.Diagnostics.Process]$batchFile
    hidden [string]$loginCmd
    hidden [string]$logoutCmd
    hidden [Hashtable]$pathTo
    hidden [string]$password
    hidden [Array]$cmdList
    hidden [Array]$filesToClean
	
    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

        IN  : $server			-> Nom DNS du serveur
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
        IN  : $certificateFile  -> Nom du fichier certificat à utiliser. Doit se
                                    trouver dans le dossier spécifié par
                                    $global:K8S_CERT_FOLDER
	#>
    TKGIKubectl([string] $server, [string]$username, [string]$password, [string]$certificateFile)
    {
        $this.password = $password
        $certificateFileFull = [IO.Path]::Combine($global:K8S_CERT_FOLDER, $certificateFile)

        # Ajout des chemins sur les binaires et test de la présence
        $this.pathTo = @{
            tkgi = [IO.Path]::Combine($global:BINARY_FOLDER, "tkgi.exe")
            kubectl = [IO.Path]::Combine($global:BINARY_FOLDER, "kubectl.exe")
        }
        
        ForEach($binName in $this.pathTo.Keys)
        {
            # On check qu'on a bien le tout pour faire le job 
            if(!(Test-Path $this.pathTo.$binName))
            {
                Throw ("Binary file '{0}.exe' is missing... (in folder {1})" -f $binName, $global:BINARY_FOLDER)
            }
        }
		
        if(!(Test-Path $certificateFileFull))
		{
			Throw ("Certificate file '{0}' is missing... (in folder {1})" -f $certificateFile, $global:K8S_CERT_FOLDER)
        }
        
        # Ligne pour se connecter à l'API
        $this.loginCmd = "{0} login -a https://{1} -u {2} -p {3} --ca-cert {4}" -f $this.pathTo.tkgi, $server, $username, $password, $certificateFileFull
        $this.logoutCmd = "{0} logout" -f $this.pathTo.tkgi

		# Création du nécessaire pour exécuter un process CURL
		$this.batchFile = New-Object System.Diagnostics.Process
		# On est obligé de mettre UseShellExecute à true sinon ça foire avec le code de retour de
		# la fonction 
		$this.batchFile.StartInfo.UseShellExecute = $false

        $this.batchFile.StartInfo.RedirectStandardOutput = $true
        $this.batchFile.StartInfo.RedirectStandardError = $true

        $this.batchFile.StartInfo.CreateNoWindow = $false

        # Reset de la liste des commandes à exécuter. Sera remplie via les méthodes:
        # - addCmd
        # - addCmdWithPassword
        $this.newBatch()
        
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Récupère le contenu d'un fichier YAML en remplaçant des valeurs si besoin.
                Le contenu du fichier YAML est mis dans un fichier temporaire et on ajoute
                celui-ci à la liste de ceux devant être "nettoyés" à la fin de l'exécution
                de la commande "exec".
        
        IN  : $file         -> Nom du fichier YAML
        IN  : $valToReplace -> Tableau associatif avec les avec les valeurs à remplacer
                                dans le fichier YAML que l'on charge.

        RET : Chaine de caractères représentant le YAML avec les infos remplacées si besoin
	#>
    hidden [string] loadYamlFile([string] $file, [System.Collections.IDictionary] $valToReplace)
	{
		# Chemin complet jusqu'au fichier à charger
		$filepath = (Join-Path $global:YAML_TEMPLATE_FOLDER $file)

		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("YAML file not found ({0})" -f $filepath)
		}

		# Chargement du code JSON
		$yaml = Get-Content -Path $filepath -raw

		# S'il y a des valeurs à remplacer
		if($null -ne $valToReplace)
		{
			# Parcours des remplacements à faire
			foreach($search in $valToReplace.Keys)
			{
                $replaceWith = $valToReplace.Item($search)
                
				$search = "{{$($search)}}"
				
				# Recherche et remplacement de l'élément
				$yaml = $yaml -replace $search, $replaceWith
			}
        }
        
        # Création d'un fichier temporaire
        $tmpYamlFile = (New-TemporaryFile).FullName
        $yaml | Out-File $tmpYamlFile -Encoding:utf8
        
        # On ajoute le fichier à ceux à effacer
        $this.filesToClean += $tmpYamlFile

        return $tmpYamlFile
	}


    <#
	-------------------------------------------------------------------------------------
        BUT : Exécute une liste de commandes sur un cluster donné
        
        IN  : $clusterName -> nom du cluster sur lequel exécuter les commandes
        
        RET : Tableau associatif avec en clef la commande passée et en valeur, le résultat (string) de
                la commande
	#>
    [System.Collections.IDictionary] exec([string]$clusterName)
    {
        $cmdFile = (New-TemporaryFile).FullName
        # On met une extension qui permettra de l'exécuter correctement par la suite via cmd.exe
        $batchFilePath = ("{0}.cmd" -f $cmdFile)
        Rename-Item -Path $cmdFile -NewName $batchFilePath

        $cmdResults = @{}
        if($this.cmdList.count -eq 0) 
        {
            return $cmdResults
        }

        # Création des lignes de commandes à exécuter
        $this.loginCmd | Out-File -FilePath $batchFilePath -Encoding:default
        # Ajout de la commande de sélection du cluster, avec authentification, puis sélection du bon contexte
        $this.getTkgiCmdWithPassword(("get-credentials {0}" -f $clusterName)) | Out-File -FilePath $batchFilePath -Append -Encoding:default
        $this.getKubectlCmd(("config use-context {0}" -f $clusterName))

        $this.cmdList | ForEach-Object{ 
            $_ | Out-File -FilePath $batchFilePath -Append -Encoding:default
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
            # On définit le séparateur en utilisant le chemin jusqu'au script:
            # Ex: PS D:\IDEVING\IaaS\git\xaas-admin\powershell>
            $separator = [string[]]@([Regex]::Matches($output, '(.*?>)(.*)').Groups[1].Value)

            # On explose les résultats des différentes commandes via le chemin jusqu'à "tkgi.exe" 
            # et on les parcoure
            $output.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {

                if($_.Trim() -eq "")
                {
                    # Passage à l'itération suivante
                    return
                }
                # Extraction du nom de la commande passée
                $cmdName = ($_ -split "`n")[0].Trim()

                # Si la commande faisait partie de ce qu'on devait exécuter
                if($this.cmdList -contains $cmdName)
                {
                    # Extraction de la commande et on double les \ dans le cas où il y aurait un chemin qui aurait été passé. Si
                    # on ne fait pas ça, on aura une erreur lors de l'exécution du "-split juste après
                    $cmdNameShort = [Regex]::Matches($cmdName, '(.*?)(tkgi|kubectl)\.exe(.*)').Groups[3].Value.Trim() -replace "\\", "\\"
                    # Ajout de la commande et de son résultat dans ce qu'on renvoie
                    $cmdResults.Add($cmdNameShort, ($_ -split $cmdNameShort)[1].Trim())
                }
            }

            

            # Suppression des éventuels fichiers temporaires
            $this.filesToClean | ForEach-Object {
                Remove-Item $_
            }

            # Reset et préparation pour le prochain batch
            $this.newBatch()
        }
        else
        {
            Throw ("Error executing commands ({0}) with error : `n{1}" -f $this.batchFile.StartInfo.Arguments, $errorStr)
        }

        return $cmdResults
    }

    
    <#
	-------------------------------------------------------------------------------------
		BUT : Fait du nettoyage pour préparer à un nouveau batch de commandes
	#>
    hidden [void] newBatch()
    {
        # Reset de la liste des commandes
        $this.cmdList = @()
        # Liste des fichiers temporaire à supprimer après l'exécution de la méthode "exec"
        $this.filesToClean = @()
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute une commande TKGI à la liste

        IN  : $command			-> La commande à exécuter
                                    Pas besoin de mettre "tkgi.exe" au début de la commande
	#>
    [void] addTkgiCmd([string]$command)
    {
        $this.cmdList += ("{0} {1}" -f $this.pathTo.tkgi, $command)
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Retourne une commande TKGI qui a besoin d'avoir à nouveau le mot de passe.
                Typiquement, la commande 'get-credentials' aura besoin du mot de passe.

        IN  : $command			-> La commande à exécuter
                                    Pas besoin de mettre "tkgi.exe" au début de la commande
	#>
    hidden [string] getTkgiCmdWithPassword([string]$command)
    {
        return ("echo({0}|{1} {2}" -f $this.password, $this.pathTo.tkgi, $command)
        
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Renvoie une commande Kubectl

        IN  : $command			-> La commande à exécuter
                                    Pas besoin de mettre "kubectl.exe" au début de la commande
	#>
    hidden [string] getKubectlCmd([string]$command)
    {
        return ("{0} {1}" -f $this.pathTo.kubectl, $command)
    }

    <#
	-------------------------------------------------------------------------------------
		BUT : Renvoie une commande Kubectl

        IN  : $command			-> La commande à exécuter
                                    Pas besoin de mettre "kubectl.exe" au début de la commande
	#>
    [void] addKubectlCmd([string]$command)
    {
        $this.cmdList += $this.getKubectlCmd($command)
    }

    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute une commande Kubectl qui envoie un fichier

        IN  : $file         -> nom du fichier Yaml à charger
        IN  : $valToReplace -> Tableau associatif avec les avec les valeurs à remplacer
                                dans le fichier YAML que l'on charge.
    #>
    [void] addKubectlCmdWithYaml([string]$file)
    {
        $this.addKubectlCmdWithYaml($file, @{})
    }
    [void] addKubectlCmdWithYaml([string]$file, [System.Collections.IDictionary] $valToReplace)
    {
        $this.cmdList += ("{0} apply -f {1}" -f $this.pathTo.kubectl, ($this.loadYamlFile($file, $valToReplace)))
    }




}