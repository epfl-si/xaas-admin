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
    hidden [Array]$cmdToOutputFile
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
        BUT : Ajoute une commande au fichier BATCH dont le chemin est passé en paramètre.
                On va aussi faire en sorte que les 2 sorties (STDERR, STDOUT) de la commande
                soient redirigées vers des fichiers, ce qui facilitera le traitement par la 
                suite vu qu'on va passer les commandes à la suite, en BATCH
        
        IN  : $command              -> commande à ajouter
        IN  : $batchFilePath        -> Chemin jusqu'au fichier Batch
    #>
    hidden [void] addCmdToBatchFile([string]$command, [string]$batchFilePath)
    {
        # Pour contenir la sortie de la commande $command et le récupérer plus facilement
        $stdoutFile = (New-TemporaryFile).FullName
        $stdErrFile = (New-TemporaryFile).FullName

        # Pour savoir où retrouver les sorties
        $this.cmdToOutputFile += @{
            cmd = $command
            stdout = $stdoutFile
            stderr = $stdErrFile
        }

        # Ajout du nécessaire pour rediriger les sorties de la commande, STDOUT et STDERR, vers des fichiers
        $command = "{0} > {1} 2> {2}" -f $command, $stdoutFile, $stdErrFile
        
        $command | Out-File -FilePath $batchFilePath -Append -Encoding:default

    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Efface les fichiers temporaires de sorties utilisés
    #>
    hidden [void] cleanOutputFiles()
    {
        $this.cmdToOutputFile | ForEach-Object {
            Remove-Item $_.stdout
            Remove-Item $_.stderr
        }
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Exécute une commande sur un cluster donné. La fonction va crééer un fichier CMD
                temporaire avec la commande de LOGIN, se positionner sur le bon cluster,
                puis la commande à exécuter et pour terminer, un LOGOUT
        
        IN  : $clusterName  -> nom du cluster sur lequel exécuter la commande
        IN  : $command      -> commande à exécuter
        IN  : $namespace    -> (optionnel) le Namespace sur lequel exécuter la commande
        
        RET : - Objet généré avec le JSON renvoyé par la commande
              - Chaine de caractères toute simple (en fonction de ce qui est renvoyé)
	#>
    [PSObject] exec([string]$clusterName, [string]$command)
    {
        return $this.exec($clusterName, $command, "")
    }
    [PSObject] exec([string]$clusterName, [string]$command, [string]$namespace)
    {
        $this.cmdToOutputFile = @()

        # Pour contenir les commandes à exécuter (login, commande, logout)
        $cmdFile = (New-TemporaryFile).FullName
        # On met une extension qui permettra de l'exécuter correctement par la suite via cmd.exe
        $batchFilePath = ("{0}.cmd" -f $cmdFile)
        Rename-Item -Path $cmdFile -NewName $batchFilePath

        $cmdResult = ""

        # Création des lignes de commandes à exécuter
        $this.addCmdToBatchFile($this.loginCmd, $batchFilePath)
        # Ajout de la commande de sélection du cluster, avec authentification, puis sélection du bon contexte
        $this.addCmdToBatchFile($this.getTkgiCmdWithPassword(("get-credentials {0}" -f $clusterName)), $batchFilePath)
        $this.addCmdToBatchFile($this.generateKubectlCmd(("config use-context {0}" -f $clusterName)), $batchFilePath)

        # Si on doit spécifier le namespace
        if($namespace -ne "")
        {
            $this.addCmdToBatchFile($this.generateKubectlCmd(("config set-context --current --namespace={0}" -f $namespace)), $batchFilePath)
        }
        
        # Ajout de la commande à exécuter avec redirection vers un fichier de sortie
        $this.addCmdToBatchFile($command, $batchFilePath)
        
        $this.addCmdToBatchFile($this.logoutCmd, $batchFilePath)

        # Log du contenu du fichier Batch
        $this.debugLog(("Batch file content:`n{0}" -f (Get-Content $batchFilePath -Raw)))

        $this.batchFile.StartInfo.FileName = $batchFilePath

        $this.batchFile.Start() | Out-Null

        # On récupère uniquement le contenu de la sortir d'erreur, pour savoir s'il y a eu une erreur.
        # Le résultat de la commande qu'on a voulu exécuter, lui, se trouvait dans le fichier $cmdResultFile
        # dans lequel on a redirigé le résultat
        $errorStr = $this.batchFile.StandardError.ReadToEnd()

        # Suppression du fichier temporaire
        if(Test-Path $batchFilePath)
        {
            Remove-Item $batchFilePath 
        }

        # Si aucune erreur
        if($this.batchFile.ExitCode -eq 0)
        {
            # Parcour des commandes exécutées
            ForEach($executedCommand in $this.cmdToOutputFile)
            {
                # Récupération de la sortie d'erreur de la commande
                $cmdStdErr = Get-Content -Path $executedCommand.stderr -Raw

                # Si la sortie contient un message d'erreur (oui parce que la sortie peut aussi contenir autre chose... 🙄)
                if($cmdStdErr -like "*Error: *")
                {
                    # Un peu de nettoyage et erreuuur !
                    $this.cleanOutputFiles()
                    Throw ([Regex]::Match($cmdStdErr, 'Error: (.*)').Groups[1].Value)
                }

                # Si c'est la commande qu'on nous a demandé d'exécuter,
                if($executedCommand.cmd.startsWith($command))
                {
                    # Récupération de la sortie de la commande
                    $cmdResult = Get-Content -Path $executedCommand.stdout -Raw

                    try
                    {
                        # On essaie de transformer le résultat en JSON
                        $cmdResult = $cmdResult | ConvertFrom-Json
                    }
                    catch
                    {
                        # En cas d'erreur, on ne fait rien, on retournera simplement la valeur de $cmdResult
                        # sans que ça soit du JSON.
                    }
                    break

                }# FIN SI C'est la commande qu'il fallait exécuter

            }# FIN BOUCLE de parcours des commandes exécutées

            $this.cleanOutputFiles()

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
    hidden [string] generateKubectlCmdWithYaml([string]$file)
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

        IN  : $clusterName      -> Nom du cluster
        IN  : $namespace        -> Nom du namespace
        IN  : $nsxEnv           -> environnement NSX (production/test/development)
        IN  : $userNamespace    -> $true|$false pour dire si Namespace utilisateur
    #>
    [void] addClusterNamespace([string]$clusterName, [string]$namespace, [DeploymentTag]$nsxEnv, [bool]$userNamespace)
    {
        if($userNamespace)
        {
            $yamlFile = "xaas-k8s-cluster-namespace-user.yaml"
        }
        else
        {
            $yamlFile = "xaas-k8s-cluster-namespace.yaml"
        }

        $replace = @{
            name = $namespace
            nsxEnv = $nsxEnv.toString().toLower()
        }
        $command = $this.generateKubectlCmdWithYaml($yamlFile, $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Efface un Namespace d'un cluster

        IN  : $clusterName  -> Nom du cluster
        IN  : $namespace    -> Nom du namespace
    #>
    [void] deleteClusterNamespace([string]$clusterName, [string]$namespace)
    {
        $command = $this.generateKubectlCmd(("delete namespace {0}" -f $namespace))

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

        return $result.items
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
    [void] addOrUpdateClusterNamespaceResourceQuota([string]$clusterName, [string]$namespace, [string]$resourceQuotaName,  [int]$nbLB, [int]$nbNodePorts, [int]$storageGB)
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
        BUT : Renvoie le Resource Quota d'un namespace d'un cluster
        
        IN  : $clusterName  -> Le nom du cluster
        IN  : $namespace    -> Le nom du namespace

        RET : Objet contenant les infos du ResourceQuota d'un namespace de cluster
            $null si pas trouvé
    #>
    [PSObject] getClusterNamespaceResourceQuota([string]$clusterName, [string]$namespace)
    {
        $result = ($this.exec($clusterName, $this.generateKubectlCmd("get resourcequota --output=json"), $namespace)).items #| Where-Object { $_.metadata.namespace -eq $namespace } 

        if($result.count -gt 1)
        {
            Throw ("Too many ResourceQuota defined ({0}) for cluster '{1}' and namespace '{2}'" -f $result.count, $clusterName, $namespace)
        }
        return $result[0]
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
    #>
    [void] addClusterRole([string]$clusterName, [string]$roleName)
    {
        $replace = @{
            name = $roleName
        }

        $command = $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-clusterRole.yaml", $replace)

        $this.exec($clusterName, $command) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un RoleBinding dans un cluster

        IN  : $clusterName      -> Nom du cluster
        IN  : $roleName         -> nom du Role 
        IN  : $roleBindingName  -> Nom du Role Binding
        IN  : $adGroupName      -> Nom du groupe AD auquel on donne les autorisations
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
		BUT : Effectue la configuration de la partie "Contour". Il s'agit de plusieurs commandes
                qui sont passées à la suite.

        IN  : $clusterName      -> Nom du cluster
    #>
    [void] configureContour([string]$clusterName)
    {
        # -- Première partie définie par l'EFPL

        $this.exec($clusterName,  $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-contour-clusterRole.yaml")) | Out-Null
        $this.exec($clusterName,  $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-contour-podSecurityPolicy.yaml")) | Out-Null
        $this.exec($clusterName,  $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-contour-roleBinding.yaml")) | Out-Null

        <# -- Partie "officielle". Tirée du fichier https://projectcontour.io/quickstart/contour.yaml 
        dans lequel on a commenté les lignes suivantes:
        service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
        externalTrafficPolicy: Local #>
        $this.exec($clusterName,  $this.generateKubectlCmdWithYaml("xaas-k8s-cluster-contour.yaml")) | Out-Null
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