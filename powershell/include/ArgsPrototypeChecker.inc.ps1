
<#
   BUT : Contient une classe permetant de contrôler que l'utilisation d'un script corresponde
         aux arguments passés pour l'exécuter. Ce fichier doit juste être inclus dans un script
         à contrôler, idéalement dans un "try...catch" histoire de pouvoir récupérer l'exception
         levée en cas de problème
         
         Les différentes possibilité d'utilisation du script doivent se trouver dans un bloc de
         commentaire multiligne (entre < # et # > , sans les espaces les espaces entre les 
         caractères) et il peut contenir plusieurs lignes de possibilités d'utilisation du 
         script. 
         Ce bloc doit IMPÉRATIVEMENT commencer par "USAGES:" (qui est défini dans $global:USAGES_KEYWORD) 
         sinon une erreur sera levée.

         S'il y a besoin d'autres informations dans un header, il faut 
         ajouter un 2e bloc de commentaire multiligne

         Les règles pour noter les utilisations sont les suivantes :
         - Chaque utilisation doit commencer par le nom du script seul (pas de ./ avant)
         - Il est possible de mettre une utilisation sur plusieurs lignes
         - Ne pas ajoute des espaces inutiles, même si ça augmente la lisibilité
         - Pour les arguments avec X valeurs possibles, le contrôle est insensible à la casse
         
         Exemple:

         test.ps1 -action setBackupTag -tag (<tag>|"")
         test.ps1 -action new -name <name> [-verbose]
         [-newLineSwitch]
         test.ps1 -action list
         test.ps1 -action get -name <name>

         Ce qui n'est PAS SUPPORTÉ:
         - Les groupes "OR" d'arguments. Dans ce cas-là, il faut faire X ligne de possibilité d'utilisation
         ... (-arg1 <value1>|-arg2 <value2>)

   ATTENTION !
   Si le script doit être exécuté via une tâche planifiée, c'est plus simple de passer par un fichier *.BAT
   intermédiaire pour faire le boulot. Dans le fichier en question, il faut utiliser la notation:
   "powershell.exe C:\path\to\myscript.ps1 -arg1 value1  > C:\save\output\to\file.log"

   Dans les options de PowerShell.exe, il est possible de spécifier le paramètre -File pour dire quel fichier 
   exécuter. Il NE FAUT PAS utiliser ce paramètre car la classe de contrôle des paramètres devient incapable
   de récupérer les paramètres d'exécution du script à contrôler.
   Et il ne faut pas non plus se dire que la ligne de commande on va la mettre directement dans la tâche planifiée,
   non. Là, on c'est la redirection vers le fichier log qui ne va plus fonctionner... 

   AUTEUR : Lucien Chaboudez
   DATE   : Août 2019

   DOCUMENTATION:
   https://confluence.epfl.ch:8443/pages/viewpage.action?pageId=101909058

   ----------
   HISTORIQUE DES VERSIONS
   20.08.2019 - 1.0 - Version de base
#>
$global:USAGES_KEYWORD="USAGES:"
class ArgsPrototypeChecker
{
    hidden [Array]$allowedUsages    # Utilisations possibles du scripts avec les arguments 
    hidden [String]$usages          # Chaine de caractères des "usages" telle que présente dans le header
    hidden [Array]$scriptCallUsage  # Manière dont le script est appelé

    # Informations sur le script 
    hidden [String]$scriptCallName  # Nom du script
    hidden [String]$scriptCallPath  # Chemin jusqu'au script
    hidden [String]$scriptCallArgs  # Arugments passés pour l'appel

    # Pour le nom du groupe d'argument courant. Cela permet de gérer un argument qui est un "ou". Ex:
    # (-arg1 <value1>|-arg2 <value2>)
    # TODO: Utiliser les données membres suivantes car pour le moment, ça a été laissé en suspend
    hidden [String]$currentArgGroupName
    hidden [int]$nbArgGroupFound

    # Tableau avec les erreurs
    hidden [Array]$errors
    

    <#
	-------------------------------------------------------------------------------------
      BUT : Créer une instance de l'objet.
            On n'a pas besoin d'informations explicites sur le script à contrôler car
            elles sont toutes trouvables en regardant l'appel qui a été fait.
	#>
    ArgsPrototypeChecker()
    {
        $callFound = $false
        $scope = 0
        $scriptCall = ""
        
        try
        {
            while (!$callFound) 
            {
                # On extrait les informations depuis la ligne de commande, on peut avoir les prototypes d'appels suivants:
                # 1: . 'd:\IDEVING\IaaS\git\xaas-admin\powershell\test.ps1' -targetEnv prod -targetTenant EPFL
                # 2: C:\scripts\git\xaas-admin\powershell\vsphere-update-vm-notes-with-tools-version.ps1 -targetEnv prod > C:\scripts\vra\scheduled\logs\vsphere-update-vm-notes-with-tools-version.log
                # 3: \xaas-s3-endpoint.ps1 -targetEnv prod -targetTenant test -action versioning -bucketName chaboude-bucket -status
                # 4: broker_serialize '& "C:\Scripts\git\xaas-admin\powershell\xaas-backup-endpoints.ps1"  -targetEnv test -action getBackupTag -vmName itstxaas0436 '
                # 5: broker_serialize 'C:\Scripts\git\xaas-admin\powershell\xaas-backup-endpoints.ps1  -targetEnv test -action getBackupTag -vmName itstxaas0436 '
                $scriptCall = (Get-Variable MyInvocation -Scope $scope).Value.Line.TrimStart(@(".")).Trim()
                $scope += 1

                # Si ce n'est pas la ligne de commande qui inclus le fichier courant pour les check, 
                if($scriptCall -notlike "*ArgsPrototypeChecker*")
                {
                    # Recherche du chemin d'appel complet, ce qui donnerait:
                    # 1: d:\IDEVING\IaaS\git\xaas-admin\powershell\test.ps1
                    # 2: C:\scripts\git\xaas-admin\powershell\vsphere-update-vm-notes-with-tools-version.ps1
                    # 3: \xaas-s3-endpoint.ps1
                    # 4: C:\Scripts\git\xaas-admin\powershell\xaas-backup-endpoints.ps1
                    # 5: C:\Scripts\git\xaas-admin\powershell\xaas-backup-endpoints.ps1
                    $this.scriptCallPath = [Regex]::Matches($scriptCall, "'?([a-zA-Z]:\\)?(([^\\:])*?\\)*([^\\])*?\.ps1'?")[0]
                    
                    if($this.scriptCallPath -ne "")
                    {
                        $callFound = $true
                    }
                }
            }
        }
        catch
        {
            # On arrive ici lorsque la valeur de $scope est trop élevée et qu'il n'existe plus rien dans MyInvocation qui satisfasse notre demande.
            Throw "ArgsPrototypeChecker: Cannot find script call info"
        }

        
        

        # Suppression de l'éventuelle redirection vers un fichier de sortie
        $pipePos = $scriptCall.IndexOf(">")
        if($pipePos -gt 0)
        {
            $scriptCall = $scriptCall.Substring(0, $pipePos).Trim()
        }

        # Extraction des paramètres
        $this.scriptCallArgs = ($scriptCall.Substring($this.scriptCallPath.length)).Trim()
        # Suppression des éventuels ' autour du nom du script
        $this.scriptCallPath = ($this.scriptCallPath -replace "'","").Trim(@(" ", "\"))
        
        $this.scriptCallName = Split-Path $this.scriptCallPath -leaf

        

        # $brokerStr = "broker_serialize"
        # if($scriptCall.StartsWith($brokerStr))
        # {
        #     # Suppression du début de la chaine et un peu de nettoyage pour arriver à  :
        #     # C:\Scripts\git\xaas-admin\powershell\xaas-backup-endpoints.ps1  -targetEnv test -action getBackupTag -vmName itstxaas0436
        #     $scriptCall = ($scriptCall.Substring($brokerStr.length).Trim(@(" ", "'", "&"))) -replace ".ps1`"", ".ps1"

        #     # On doit aussi nettoyer cette variable car elle ressemble à l'une d'elle:
        #     # broker_serialize '& "C:\Scripts\git\xaas-admin\powershell\xaas-backup-endpoints.ps1
        #     # broker_serialize 'C:\Scripts\git\xaas-admin\powershell\xaas-backup-endpoints.ps1
        #     $this.scriptCallPath = ($this.scriptCallPath.Substring($brokerStr.length)).Trim(@(" ", "'", "&"))
        # }
        
        # # Suppression début de la ligne avec le nom du script (et le chemin). Reste donc que les paramètres 
        # $scriptCall = $scriptCall.Substring(($scriptCall.IndexOf($this.scriptCallPath)+ $this.scriptCallPath.length)).Trim()

        

        # # Suppression des éventuels ' autour du nom du script
        # $this.scriptCallPath = ($this.scriptCallPath -replace "'","").Trim(@(" ", "\"))
        

        # # On récupère les arguments
        # $this.scriptCallArgs = $scriptCall

        $this.allowedUsages = @()

        $this.currentArgGroupName = ""
        $this.nbArgGroupFound = 0

        $this.errors = @()
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Parse les arguements possibles pour l'utilisation (usage) passée en paramètre

      IN  : $usage  -> Chaîne de caractères représentant une utilisation possible du script.
                        Celle-ci provient du heander du script.

      RET : Tableau avec la liste des arguments    
	#>
    hidden [Array] parseUsageArgs([string]$usage)
    {
        # Pour les informations que l'on va retourner
        $usageArgsInfos = @{nbMandatoryArgs = 0
                            Args = @()}

        # Extraction des arguments (et des valeurs potentielles)
        $usageArgs = $usage.Split(" ") 

        # Parcours des arguments du Usage courant
        For($argIndex=0; $argIndex -lt $usageArgs.Count; $argIndex++)
        {
            $argInfos = @{Name = ""               # Nom de l'argument 
                          Values = @()          # Tableau avec valeurs possibles, si harcodée: "-arg value"  ou alors "-arg value1|value2"
                                                # $null = n'importe quelle valeur sauf chaine vide.
                                                # Si ce tableau est vide, c'est que c'est un switch
                          Mandatory = $true       # Pour dire si obligatoire
                          groupName = $null}      # Nom du groupe de paramètre 
                          
            
            $arg = $usageArgs[$argIndex].Trim(@(" ", "`t"))

            # Si c'est un argument optionnel
            # Ex [-targetEnv
            if($arg.StartsWith("["))
            {
                $argInfos.Mandatory = $false

                # On nettoie l'argument pour enlever les [ ]
                # [-targetEnv] -> -targetEnv
                # [-targetEnv  -> -targetEnv  (si pas Switch)
                $arg = $arg.trim(@("[", "]"))
            }
            
            # TODO: Code volontairement commenté car on ne gère pas encore ceci pour le moment, c'est un peu trop complexe
            # à mettre en place à première vue
            # Si on tombe sur groupe d'arguments,
            # Ex: (-targetEnv 
            # if($arg.StartsWith("(-"))
            # {
            #     # Si on est déjà dans un groupe d'arguments, on propage une exception
            #     if($this.currentArgGroupName -ne "")
            #     {
            #         Throw ("Nested argument groups not supported ({0})" -f $arg)
            #     }
            #     # Initialisation du nom du groupe 
            #     $this.currentArgGroupName = "argGroup{0}" -f $this.nbArgGroupFound
            #     $this.nbArgGroupFound +=1

            #     # Nettoyage
            #     # (-targetEnv  -> -targetEnv
            #     $arg = $arg.trim(@("("))
            # }

            # Si c'est un argument (et pas une valeur )
            # Ex: -targetEnv
            if($arg.StartsWith("-"))
            {
                $argInfos.Name = $arg
                # Mise à jour du groupe potentiel dans lequel se trouve l'argument
                $argInfos.groupName = $this.currentArgGroupName             

                $usageArgsInfos.args += $argInfos

                # Si c'est un argument obligatoire et qu'on n'est pas dans un groupe d'arguments
                if($argInfos.Mandatory -and ($this.currentArgGroupName -eq ""))
                {
                    $usageArgsInfos.nbMandatoryArgs += 1   
                }

            }
            else # C'est une valeur 
            {
                # Si plusieurs valeurs possible et que celles-ci ont été mises entre ( )
                if($arg.StartsWith("("))
                {
                    # On fait un peu de nettoyage 
                    $arg = $arg.Trim(@("(", ")"))
                }

                # Parcours des valeurs possibles (s'il y en a plusieurs )
                $arg.Split("|") | ForEach-Object {
                    # Si c'est une valeur hardcodée
                    if(!($_.StartsWith("<")))
                    {
                        # Initialisation de la valeur autorisée
                        $allowedValue = $_.ToLower()
                    }
                    else
                    {
                        # On initialise avec $null pour dire que n'importe quelle valeur (sauf chaine vide) est autorisée
                        $allowedValue = $null
                    }

                    # On l'assigne à l'argument précédemment rencontré 
                    $usageArgsInfos.Args[$usageArgsInfos.Args.Count -1].Values += $allowedValue

                }# FIN BOUCLE de parcours des valeurs possibles 

            }# FIN SI c'est une valeur


        }# FIN BOUCLE de parcours des arguments du Usage courant

        # Mise à jour du nombre d'arguments obligatoires en additionnant le nombre de groupes rencontrés aux arguments obligatoires rencontrés
        $usageArgsInfos.nbMandatoryArgs += $this.nbArgGroupFound

        return $usageArgsInfos
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Détermine si l'argument d'utilisation passé (pour une utilisation donnée) 
            est OK par rapport aux arguments passés au script pour son exécution

      IN  : $allowedUsageArgInfos  -> Informations sur l'argument (d'une utilisation donnée) 
                                        que l'on veut contrôler

      RET : $true|$false pour dire si c'est OK ou pas.
	#>
    hidden [bool] callArgIsCorrect($allowedUsageArgInfos)
    {
        # Parcours des arguments utilisés pour appeler le script
        ForEach($callArg in $this.scriptCallUsage.Args)
        {
            # Si on tombe sur un argument d'une utilisation du script qui correspond 
            if($callArg.Name -eq $allowedUsageArgInfos.Name)
            {
                # Si l'argument est un switch, pas besoin de faire plus de check, on est bon
                if($allowedUsageArgInfos.Values.Count -eq 0)
                {
                    return $true
                }

                # Arrivé ici, c'est que l'argument n'est pas un switch, il faut donc
                # contrôler les valeurs autorisées pour celui-ci s'il y en a

                # Parcours des valeurs autorisées 
                ForEach($allowedValue in $allowedUsageArgInfos.Values)
                {
                    # Si on peut mettre n'importe quelle valeur sauf "" et que
                    # la valeur de l'argument (index 0 de .Values) n'est pas ""
                    # OU 
                    # Si la valeur de l'appel correspond à une autorisée
                    if( (($null -eq $allowedValue) -and ($callArg.Values[0] -ne "")) -or 
                        ($callArg.Values[0].toLower() -eq $allowedValue))
                    {
                        # On supprime les erreurs précédemment ajoutées s'il y en avait
                        $this.errors = @()
                        return $true
                    }

                }# FIN BOUCLE de parcours des valeurs autorisées

                # Ajout de l'erreur à la liste si elle n'y est pas encore
                # FIXME: Dans le cas où un argument peut prendre plusieurs valeurs (une par utilisation entrée), on va générer une erreur
                # fausse qui dira que la valeur du paramètre est incorrecte
                $err = "(this error may be false) Incorrect value ({0}) for argument {1}" -f $callArg.Values[0], $callArg.Name
                if($this.errors -notcontains $err)
                {
                    $this.errors += $err
                }
                
                # On peut sortir car on ne va pas tomber sur un autre argument avec le même nom...
                break
            }# FIN SI on tombe sur l'arguement qui a le même nom 

        }# FIN BOUCLE de parcours des arguments utilisés pour l'appel du script

        # Si on arrive ici, c'est qu'on n'a pas trouvé l'argument de l'appel dans ceux autorisé pour l'utilisation possible donnée
        return $false
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Parse le header du script afin d'extraire les différentes utilisations qui y sont
            mentionnées et analyse ensuite celles-ci
	#>
    [void] parseScriptHeader()
    {
        # Extraction de la liste des utilisations
        $this.usages = ([Regex]::Matches((Get-content $this.scriptCallPath), ("<#\s*{0}\s*.*?#>" -f $global:USAGES_KEYWORD)))[0]

        # Si rien n'a été trouvé... 
        if($this.usages -eq "")
        {
            Throw ("Usages multi-lines comment not found! Needs to start with '{0}'" -f $global:USAGES_KEYWORD)
        }
        # Nettoyage pour virer ce qui est avant/après
        $this.usages = $this.usages -replace $global:USAGES_KEYWORD, ""
        $this.usages = ([String]$this.usages).Trim(@("<", ">", "#", "`t", " "))

        # Lecture de l'entête du script et parcours des "usages"
        $this.usages -Split $this.scriptCallName | ForEach-Object {
            
            # Nettoyage de la ligne du usage courant
            $cleanedUsage = $_.Trim(@(" ", "`t"))

            # Si après nettoyage il reste quelque chose du Usage... 
            if($cleanedUsage -ne "" )
            {
                
                <# On ajoute les informations du Usage courant à la liste. La virgule n'est pas une faute de frappe,
                elle permet d'ajouter le nouvel élément comme étant un nouvel élément du tableau $usages. Si on ne
                la met pas, ça va simplement fusionner le tableaux $usages et $currentUsageParams, et on ne veut pas ça...#>
                $this.allowedUsages += , $this.parseUsageArgs($cleanedUsage)

            }# FIN SI il reste quelque chose du Usage après nettoyage 

        }# FIN BOUCLE de parcours des Usages
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Parse l'appel du script pour extraire les informations
	#>
    [void] parseScriptCall()
    {
        $this.scriptCallUsage = $this.parseUsageArgs($this.scriptCallArgs)
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Valide que l'appel au script est correct
	#>
    [void] validateScriptCall()
    {
        $callOk = $false

        # Parcours des utilisations possibles
        ForEach($allowedUsage in $this.allowedUsages)
        {

            $nbArgsOK = 0

            # Parcours des arguments possibles pour l'utilisation courante 
            Foreach($allowedUsageArgInfos in $allowedUsage.Args) 
            {
                # Si l'argument est OK dans l'appel qui a été fait au script
                if($this.callArgIsCorrect($allowedUsageArgInfos))
                {
                    $nbArgsOK += 1
                }
            } # FIN boucle parcours des arguments possibles 

            # Si on a trouvé un match pour l'appel du script
            if($nbArgsOK -ge $allowedUsage.nbMandatoryArgs)
            {
                $callOk = $true
                # on peut sortir de la boucle 
                Break
            }

        }# FIN BOUCLE parcours des utilisations possibles 


        if(!$callOk)
        {
            Throw ("Incorrect arguments given. {0}`nUsage is:{1}" -f ($this.errors -join "\n"), ($this.usages -replace $this.scriptCallName, ("`n{0}" -f $this.scriptCallName)) )
        }
    }

}

$argsChecker = [ArgsPrototypeChecker]::New()
$argsChecker.parseScriptHeader()


<# Arrivé ici, le paramètre $usages contient un descritif des possibilités d'utilisation du script telle que définies dans le header de celui-ci
   On peut maintenant passer à la partie où on parcours ces Usages afin de voir si l'utilisation qui est faite du script est correcte ou pas #>


$argsChecker.parseScriptCall()
$argsChecker.validateScriptCall()

