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
    hidden [Array]$filesToClean
    hidden [LogHistory] $logHistory
	
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
        $this.logHistory = $null

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

        $this.filesToClean = @()
        
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
        $inputFileName = Split-Path $file -Leaf

		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("YAML file not found ({0})" -f $filepath)
		}

		# Chargement du code JSON
		$yaml = Get-Content -Path $filepath -raw -Encoding:UTF8

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
        $tmpYamlFile = ("{0}-{1}" -f (New-TemporaryFile).FullName, $inputFileName)

        $yaml | Out-File $tmpYamlFile -Encoding:utf8

        $this.debugLog( ("Creating YAML (from {0}) and final content is:`n{1}`n" -f $inputFileName, $yaml))
        
        # On ajoute le fichier à ceux à effacer
        $this.filesToClean += $tmpYamlFile

        return $tmpYamlFile
	}


    <#
	-------------------------------------------------------------------------------------
        BUT : Exécute une commande sur un cluster donné
        
        IN  : $clusterName  -> nom du cluster sur lequel exécuter la commande
        IN  : $command      -> commande à exécuter
        
        RET : Tableau associatif avec en clef la commande passée et en valeur, le résultat (string) de
                la commande
	#>
    [string] exec([string]$clusterName, [string]$command)
    {
        $cmdFile = (New-TemporaryFile).FullName
        # On met une extension qui permettra de l'exécuter correctement par la suite via cmd.exe
        $batchFilePath = ("{0}.cmd" -f $cmdFile)
        Rename-Item -Path $cmdFile -NewName $batchFilePath

        $cmdResult = ""

        # Création des lignes de commandes à exécuter
        $this.loginCmd | Out-File -FilePath $batchFilePath -Encoding:default
        # Ajout de la commande de sélection du cluster, avec authentification, puis sélection du bon contexte
        $this.getTkgiCmdWithPassword(("get-credentials {0}" -f $clusterName)) | Out-File -FilePath $batchFilePath -Append -Encoding:default
        $this.generateKubectlCmd(("config use-context {0}" -f $clusterName)) | Out-File -FilePath $batchFilePath -Append -Encoding:default

        # Ajout de la commande à exécuter
        $command | Out-File -FilePath $batchFilePath -Append -Encoding:default
        
        $this.logoutCmd | Out-File -FilePath $batchFilePath -Append -Encoding:default

        $this.batchFile.StartInfo.FileName = $batchFilePath

        $this.batchFile.Start() | Out-Null

        $output = $this.batchFile.StandardOutput.ReadToEnd()
        $errorStr = $this.batchFile.StandardError.ReadToEnd()

        $this.debugLog(("TKGIKubectl Exec stdError content:`n{0}`n" -f $errorStr))

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
            ForEach($cmdOutput in $output.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries))
            {

                if($cmdOutput.Trim() -eq "")
                {
                    # Passage à l'itération suivante
                    continue
                }
                # Extraction du nom de la commande passée
                $currentCmd = ($cmdOutput -split "`n")[0].Trim()

                # Si la commande faisait partie de ce qu'on devait exécuter
                if($command -eq $currentCmd)
                {
                    # Extraction de la commande et on double les \ dans le cas où il y aurait un chemin qui aurait été passé. Si
                    # on ne fait pas ça, on aura une erreur lors de l'exécution du "-split juste après
                    $currentCmdShort = [Regex]::Matches($currentCmd, '(.*?)(tkgi|kubectl)\.exe(.*)').Groups[3].Value.Trim() -replace "\\", "\\"
                    # Ajout de la commande et de son résultat dans ce qu'on renvoie
                    $cmdResult = ($cmdOutput -split $currentCmdShort)[1].Trim()
                    
                    $this.debugLog(("TKGIKubectl exec command outputs.`nCommand: {0}`nOutput: {1}`n" -f $currentCmdShort, $cmdResult))

                    # On a trouvé le résultat de la commande exécutée, donc on sort
                    break
                }
            }

            # Suppression des éventuels fichiers temporaires
            $this.filesToClean | ForEach-Object {
                Remove-Item $_
            }

            $this.filesToClean = @()

        }
        else
        {
            Throw ("Error executing commands ({0}) with error : `n{1}" -f $this.batchFile.StartInfo.Arguments, $errorStr)
        }

        

        return $cmdResult
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Renvoie une commande TKGI

        IN  : $command			-> La commande à exécuter
                                    Pas besoin de mettre "tkgi.exe" au début de la commande
	#>
    [string] generateTkgiCmd([string]$command)
    {
        return ("{0} {1}" -f $this.pathTo.tkgi, $command)
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
		BUT : Génère une commande Kubectl

        IN  : $command			-> La commande à exécuter
                                    Pas besoin de mettre "kubectl.exe" au début de la commande
	#>
    hidden [string] generateKubectlCmd([string]$command)
    {
        return ("{0} {1}" -f $this.pathTo.kubectl, $command)
    }

    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute une commande Kubectl qui envoie un fichier

        IN  : $file         -> nom du fichier Yaml à charger
        IN  : $valToReplace -> Tableau associatif avec les avec les valeurs à remplacer
                                dans le fichier YAML que l'on charge.
    #>
    hidden [string] genereateKubectlCmdWithYaml([string]$file)
    {
        return $this.generateKubectlCmdWithYaml($file, @{})
    }
    hidden [string] generateKubectlCmdWithYaml([string]$file, [System.Collections.IDictionary] $valToReplace)
    {
        return ("{0} apply -f {1}" -f $this.pathTo.kubectl, ($this.loadYamlFile($file, $valToReplace)))
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un storageClass à un cluster

        IN  : $clusterName      -> Nom du cluster
        IN  : $storageClassName -> Nom du StorageClass
        IN  : $provisioner      -> Provisioner
        IN  : $datastore        -> datastore
    #>
    [void] addClusterStorageClass([string]$clusterName, [string]$storageClassName, [string]$provisioner, [string]$datastore)
    {
        $replace = @{
            name = $storageClassName
            provisioner = $provisioner
            datastore = $datastore
        }
        
        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-storageClass.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un Namespace à un cluster

        IN  : $clusterName  -> Nom du cluster
        IN  : $namespace    -> Nom du namespace
        IN  : $nsxEnv       -> environnement NSX (prod/test/dev)
    #>
    [void] addClusterNamespace([string]$clusterName, [string]$namespace, [string]$nsxEnv)
    {
        $replace = @{
            name = $namespace
            nsxEnv = $nsxEnv
        }
        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-namespace.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des namespaces d'un cluster
        
        IN  : $clusterName  -> Le nom du cluster

        RET : Liste des objets représentants les namespaces. Il faut aller regarder dans 
                "metadata.name" pour avoir le nom
    #>
    [Array] getClusterNamespaceList([string]$clusterName)
    {
        $result = $this.exec($clusterName, $this.generateKubectlCmd("get namespaces --output=json"))

        # Filtre pour ne pas renvoyer certains namespaces "system"
        $ignoreFilterRegex = "(kube|nsx|pks)-.*"

        return ($result | ConvertFrom-Json).items | `
            Where-Object { $_.metadata.name -notmatch $ignoreFilterRegex }
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un ResourceQuota à un namespace dans un cluster

        IN  : $clusterName          -> Nom du cluster
        IN  : $namespace            -> Nom du namespace
        IN  : $resourceQuotaName    -> Nom du ResourceQuota
        IN  : $nbLB                 -> nombre de load balancers
        IN  : $nbNodePorts          -> Nombre de node ports
        IN  : $storageGB            -> Taille allouée en GB
    #>
    [void] addClusterNamespaceResourceQuota([string]$clusterName, [string]$namespace, [string]$resourceQuotaName,  [int]$nbLB, [int]$nbNodePorts, [int]$storageGB)
    {
        $replace = @{
            name = $resourceQuotaName
            namespace = $namespace
            nbLoadBalancers = $nbLB
            nbNodePorts = $nbNodePorts
            storageGi = $storageGB
        }
     
        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-resourceQuota.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des Resource Quota d'un namespace d'un cluster
        
        IN  : $clusterName  -> Le nom du cluster
        IN  : $namespace    -> Le nom du namespace

        RET : Liste des objets représentants les Resource Quota. Il faut aller regarder dans 
                "metadata.name" pour avoir le nom
    #>
    [Array] getClusterNamespaceResourceQuotaList([string]$clusterName, [string]$namespace)
    {
        $result = $this.exec($clusterName, $this.generateKubectlCmd("get resourcequota --output=json"))

        return ($result | ConvertFrom-Json).items | `
            Where-Object { $_.metadata.namespace -eq $namespace } 
    }
    

    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un Pod Security Policy dans un cluster

        IN  : $clusterName              -> Nom du cluster
        IN  : $pspName                  -> Nom du Pod Security Policy
        IN  : $privileged               -> Privileged
        IN  : $allowPrivilegeEscalation -> Allow privilege escalation
    #>
    [void] addClusterPodSecurityPolicy([string]$clusterName, [string]$pspName, [bool]$privileged, [bool]$allowPrivilegeEscalation)
    {
        $replace = @{
            name = $pspName
            privileged = $privileged
            allowPrivilegeEscalation = $allowPrivilegeEscalation
        }

        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-podSecurityPolicy.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un Role pour un namespace dans un cluster

        IN  : $clusterName  -> Nom du cluster
        IN  : $namespace    -> Nom namespace
        IN  : $roleName     -> nom du Role que l'on veut ajouter
    #>
    [void] addClusterNamespaceRole([string]$clusterName, [string]$namespace, [string]$roleName)
    {
        $replace = @{
            name = $roleName
            namespace = $namespace
        }

        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-role.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un RoleBinding pour un role dans un namespace dans un cluster

        IN  : $clusterName  -> Nom du cluster
        IN  : $namespace    -> Nom namespace
        IN  : $roleName     -> nom du Role 
        IN  : $roleBinding  -> Nom du RoleBinding à ajouter
        IN  : $adGroupName  -> Nom du groupe AD 
    #>
    [void] addClusterNamespaceRoleBinding([string]$clusterName, [string]$namespace, [string]$roleName, [string]$roleBindingName, [string]$adGroupName)
    {
        $replace = @{
            name = $roleBindingName
            namespace = $namespace
            groupName = $adGroupName
            roleName = $roleName
        }

        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-roleBinding.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un Role dans un cluster

        IN  : $clusterName  -> Nom du cluster
        IN  : $roleName     -> nom du Role 
        IN  : $pspName      -> Nom du Pod Security Policy lié
    #>
    [void] addClusterRole([string]$clusterName, [string]$roleName, [string]$pspName)
    {
        $replace = @{
            name = $roleName
            pspName = $pspName
        }

        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-clusterRole.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un Role dans un cluster

        IN  : $clusterName  -> Nom du cluster
        IN  : $roleName     -> nom du Role 
        IN  : $pspName      -> Nom du Pod Security Policy lié
    #>
    [void] addClusterRoleBinding([string]$clusterName, [string]$roleName, [string]$roleBindingName, [string]$adGroupName)
    {
        $replace = @{
            name = $roleBindingName
            groupName = $adGroupName
            clusterRoleName = $roleName
        }

        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-clusterRoleBinding.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Activation du logging "debug" des requêtes faites sur le système distant.

		IN  : $logHistory	-> Objet de la classe LogHistory qui va permettre de faire le logging.
	#>
	[void] activateDebug([LogHistory]$logHistory)
	{
		$this.logHistory = $logHistory
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une ligne au debug si celui-ci est activé

		IN  : $line	-> La ligne à ajouter
	#>
	[void] debugLog([string]$line)
	{
		if($null -ne $this.logHistory)
		{
			$funcName = ""

			ForEach($call in (Get-PSCallStack))
			{
				if($call.FunctionName -ne "debugLog")
				{
					$funcName = $call.FunctionName
					break
				}
			}
			
			$this.logHistory.addDebug(("{0}::{1}(): {2}" -f $this.GetType().Name, $funcName, $line))
		}
	}




}