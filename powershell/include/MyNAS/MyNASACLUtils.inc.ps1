<# --------------------------------------------------------------------------------
 BUT : Classe fournissant les primitives pour gérer les ACL des utilisateurs
 
 AUTEUR : Lucien Chaboudez
 DATE	 : 28.10.2011

 PREREQUIS : 1. Installer la version appropriée (x86 ou x64) de Quest ActiveRolesManagement 
             2. Autoriser les scripts powershell à s'exécuter sans signature
                Set-ExecutionPolicy Unrestricted
             3. S'assurer que l'exécutable "fileacl.exe" soit dans le même dossier que le script. 
                Celui-ci peut être trouvé ici : http://www.gbordier.com/gbtools/fileacl.asp

 -------------------------------------------------------------------------------- #>


 class MyNASACLUtils
 {
    hidden [string] $logDir
    hidden [string] $currentLogFile
    hidden [string] $fileACL
    hidden [NameGeneratorMyNAS] $nameGeneratorMyNAS
    hidden [LogHistory] $logHistory

    <#
        -------------------------------------------------------------------------------------
        BUT : Constructeur de classe
        
        IN  : $logDir       -> Chemin jusqu'au dossier de logs
        IN  : $binDir       -> Chemin jusqu'au dossier où sont les binaires
    #>
    MyNASACLUtils([string]$logDir, [string]$binDir, [NameGeneratorMyNAS]$nameGeneratorMyNAS, [LogHistory]$logHistory)
    {
        $this.logDir = $logDir
        $this.fileACL = Join-Path $binDir "fileacl.exe"
        $this.nameGeneratorMyNAS = $nameGeneratorMyNAS
        $this.logHistory = $logHistory

        # Existance de FileAcl 
        if(!(Test-Path $this.fileACL))
        {
            Throw ("Error! '{0}' is missing" -f $this.fileACL)
        }

    }


    

    <#
        -------------------------------------------------------------------------------------
        BUT : Défini le chemin jusqu'au dossier où mettre les logs pour un serveur "files[0-9]",
                créé le dossier si n'existe pas et le renvoie
        
        IN  : $server        -> nom du serveur

        RET : chemin jusqu'au dossier de logs pour le serveur
    #>
    hidden [string]initServerLogDir([string]$server)
    {
        $serverLogDir = ([IO.Path]::Combine($this.logDir, $server))

        # Si le dossier n'existe pas, on le créé
        if(!(Test-Path $serverLogDir -PathType Container))
        {
            New-Item $serverLogDir -ItemType directory | Out-Null
        }

        return $serverLogDir
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Défini le chemin jusqu'au fichier dans lequel on va stocker le log pour l'utilisateur
        
        IN  : $server       -> nom du serveur
        IN  : $username     -> username     

        RET : chemin jusqu'au fichier log pour l'utilisateur
    #>
    hidden [void] initUserLogFile([string]$server, [string]$username)
    {
        $this.currentLogFile = Join-Path ($this.initServerLogDir($server)) "$username.log"
    }



    <#
        -------------------------------------------------------------------------------------
        BUT : Ajoute une ligne dans le fichier LOG
        
        IN  : $message      -> le message à ajouter. Si on met vide (""), cela aura pour effet
                                d'ajouter une ligne vide dans le fichier log
    #>
    hidden [void] writeToLog([string]$message)
    {
        if($message -eq "")
        {
            $line = '`n'            
        }
        else
        {
            $line = "{0}: {1}" -f (Get-Date -f "yyyy.MM.dd - HH:mm:ss"), $message
        }

        $line | Out-File $this.currentLogFile -Append:$true
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Ajoute une ligne dans le fichier LOG et l'affiche à l'écran aussi
        
        IN  : $message      -> le message à ajouter. Si on met vide (""), cela aura pour effet
                                d'ajouter une ligne vide dans le fichier log
        IN  : $displayRed   -> $true|$false pour dire si on doit afficher en rouge    
    #>
    hidden [void] writeToLogAndHost([string]$message) 
    {
        $this.writeToLogAndHost($message, $false)
    }
    hidden [void] writeToLogAndHost([string]$message, [bool]$displayRed) 
    {  
    
        $this.writeToLog($message)

        if($displayRed)
        {
            $this.logHistory.addLineAndDisplay($message, "red", "black")
        }
        else
        {
            $this.logHistory.addLineAndDisplay($message)
        }
        
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Exécute une commande avec "fileacl.exe"
        
        IN  : $fileACLArgs      -> arguments pour l'exécution de fileacl.exe
        IN  : $returnOutput     -> $true|$false pour dire de retourner l'output
    #>
    hidden [string] runFileACL([string]$fileACLArgs)
    {
        return $this.runFileACL($fileACLArgs, $false)
    }
    hidden [string] runFileACL([string]$fileACLArgs, [bool]$returnOutput)
    {
    # ----- Création du process pour exécuter Fileacl 
    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = $this.fileACL
        
    if($returnOutput)
    {
        $processStartInfo.UseShellExecute = $false
    }
    else
    {
        # On est obligé de mettre UseShellExecute à true sinon ça foire avec le code de retour de
        # la fonction 
        $processStartInfo.UseShellExecute = $true
    }

    $processStartInfo.RedirectStandardOutput = $returnOutput

    $processStartInfo.CreateNoWindow = $false
        # -----

    $processStartInfo.Arguments = $fileACLArgs
        
    $fileAclProcess = [System.Diagnostics.Process]::Start($processStartInfo)

    if($returnOutput)
    {
        $output = $fileAclProcess.StandardOutput.ReadToEnd()
    }
    else
    {
        $output = ""
    }

    $fileAclProcess.WaitForExit()

    if($fileAclProcess.ExitCode -ne 0)
    {
        Throw ("Error executing command with parameters ({0}). Exit code: {1}" -f $fileACLArgs, $fileAclProcess.ExitCode)
    }

    return $output
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie un tableau avec les informations d'un utilisateur du domaine
        
        IN : $username		-> le nom du user

        RET : Objet
            .domainShortName
            .domainFullName
            .userSID
    #>
    hidden [PSObject] searchDomainUserInfos([string]$username) 
    {
        # Récupération du DN complet :
        # EX: CN=Chaboudez Lucien,OU=DIT-EX-Users,OU=DIT-EX,OU=P-DIT,OU=P,DC=intranet,DC=epfl,DC=ch     
        try
        {
            $val = Get-ADUser -Identity $username -Properties * 
        }
        catch
        {
            $this.writeToLogAndHost(("No AD user found for '{0}'"  -f $username), $true)
            # Si on arrive ici, c'est que l'utilisateur n'existe pas dans AD
            return $null
        }
    
        # Split avec "DC=" pour obtenir un tableau avec 
        # ( "CN=Chaboudez Lucien,OU=DIT-EX-Users,OU=DIT-EX,OU=P-DIT,OU=P,", "intranet,", "epfl,", "ch")
        $array = $val.DistinguishedName.Split(@("DC="), [StringSplitOptions]::None)
    
        $domain = ""
        $domainShortName=""
        $i=1
        # Parcours du tableau pour recréer le FQDN du domaine
        while($i -lt $array.Count)
        {
            if($domain -ne "" ) { $domain += "." }
            $domain += $array[$i].Split(",")[0];
            if($i -eq 1) { $domainShortName = $domain}
            $i++
        }
    
        # --- Recherche du SID 
        $objUser = New-Object System.Security.Principal.NTAccount($username)
        $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
    
        return @{
            domainShortName = $domainShortName
            domainFullName = $domain
            userSID = $strSID.Value
        }
    
    }


    <#
        -------------------------------------------------------------------------------------
        BUT: Recherche les fichiers exécutables (par un user) dans un dossier ainsi que tous les SID se trouvant
        dans les ACLs	
    
        IN : $directory		 		    -> le dossier où chercher
        IN : $forDomainBackslashUser	-> le nom du user (sous la forme <domaine>\<username>) pour lequel rechercher
                                            les fichiers exécutables 
        IN  : $SIDToSkip                -> tableau avec la liste des SID à sauter
        
        ref: http://msdn.microsoft.com/en-us/library/system.diagnostics.processstartinfo.aspx
        ref:  http://msdn.microsoft.com/en-us/library/system.diagnostics.process.aspx

    #>
    hidden [PSObject] searchExecFilesForUserAndAllSID([string]$directory, [string]$forDomainBackslashUser, [array]$SIDToSkip)
    {
        
        # Droits qui permettent d'avoir le "exec"
        $execRights= @("ReadAndExecute", "FullControl");

        # Tableau de résultats 
        $res = @{
            filesWithExec = @()
            filesAndSID = @()
        }
        
        $nbFilesAnalyzed = 0
        Write-Host "`r$nbFilesAnalyzed files processed... " -NoNewline
    
        # ----- Parcours des fichiers 
        
    foreach($fileOrFolder in (Get-ChildItem -Path $directory -recurse )) #  | Where-Object { $_.Attributes -notlike "*directory*"}))
    {
            
            $nbFilesAnalyzed++
            if( ($nbFilesAnalyzed % 100) -eq 0)
            {
                Write-Host "`r$nbFilesAnalyzed files processed... " -NoNewline
            }
    
            # Comme il se peut que l'on tombe sur des fichiers sur lesquels on ne peut pas lire les ACLs, on fait une 
            # gestion des exceptions. 
            try 
            {
                # Parcours des ACLs pour l'utilisateur défini
                foreach($aclEntry in ($fileOrFolder | Get-Acl | Select-Object Access).Access | Where-Object {$_.IdentityReference -eq $forDomainBackslashUser})
                {
                
                    # Si c'est une ACL "Allow", on traite
                    if(($aclEntry | Select-Object -ExpandProperty AccessControlType ).ToString().Equals("Allow"))
                    {
                        # Droits de l'utilisateur 
                        $aclRights = ($aclEntry | Select-Object -ExpandProperty FileSystemRights)
                        $aclRightsArray = $aclRights.ToString().Split(",")
                        # Parcours des droits
                        foreach($right in $aclRightsArray) 
                        {	# Si le droit "exec" est mis, 
                            if($execRights -contains $right.Trim())
                            {
                                # Enregistrement du nom du fichier/dossier (avec chemin complet)
                                $res.filesWithExec += $fileOrFolder.FullName
                            }
                        } # FIN Boucle parcours des droits
                    } # FIN Si c'est une ACL 'Allow'
                } # FIN Boucle parcours des ACLs du fichier courant
            }
            catch # S'il y a une exception, 
            {
                # On ne fait rien en cas d'exception, 
            }
                
        } # FIN Boucle parcours récursif des fichier d'un dossier 
    
        Write-Host "`r$nbFilesAnalyzed files processed!     " 
    
        $this.writeToLogAndHost("Extracting SIDs...")
    
        $nbSIDExtracted = 0
        Write-Host "`r$nbSIDExtracted SID extracted... " -NoNewline
    
        # Extraction des SID de tous les fichiers
        $SIDList = $this.runFileACL("$directory /raw /files /sub", $true)
    
        # S'il y a des SID (donc des fichiers trouvés, )
        if(($null -ne $SIDList) -and ($SIDList -ne ""))
        {
            $SIDList = $SIDList.Split("`n", [stringSplitOptions]::RemoveEmptyEntries)
        
            if($SIDList.Count -le 200){$dispEvery = 10;}else{$dispEvery = 100;}
    
            # Parcours de la liste des SID
            foreach($SIDInfos in $SIDList)
            {
        
                if( ($nbSIDExtracted % $dispEvery) -eq 0)
                {
                    Write-Host "`r$nbSIDExtracted SID extracted... " -NoNewline
                }
    
                # Extraction SID
                # $SID sous la forme : "M:\filemon.exe;S-1-5-21-57989841-436374069-839522115-19799:0x1f01ff"
                $SID = ((($SIDInfos.Split(";"))[1]).Split(":"))[0]
                # S'il ne faut pas skip le SID courant, 
                if($SIDToSkip -notcontains $SID)
                {
                    $nbSIDExtracted++
                    # Enregistrement
                    $res.filesAndSID += $SIDInfos;
                }

            } # FIN BOUCLE parcours des SID

        }# FIN S'il y a des SID
    
        Write-Host "`r$nbSIDExtracted SID extracted... "
    
        return $res
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Affiche une barre de progression
    
        IN  : $stepNo      -> numéro de l'étape courante (ou nombre d'éléments traités jusqu'à maintenant)
        IN  : $stepTot     -> nombre total d'étapes (ou nombre total d'éléments à traiter)
        IN  : $text        -> le texte à afficher avant la barre
    #>
    hidden [void] dispProgress([int] $stepNo, [int] $stepTot, [string]$text)
    {
        
        # Taille de la barre
        $BAR_SIZE=50
        $BAR_CHAR="="
        $BAR_END_CHAR=">"
        
        # Calcul du pourcentage d'avancement
        $percent=[int]($stepNo / $stepTot * 100)
        # Nombre de caractères pour l'affichage de la barre
        $nbChar = [int]($stepNo / $stepTot * $BAR_SIZE)
        
        # Création de la chaine à afficher 
        $toDisp = ""
        if($text -ne ""){ $toDisp = "$text "; }
        
        $toDisp += "["
        if( ($nbChar-1) -gt 0) {$toDisp = $toDisp.padRight(($nbChar-1+$toDisp.Length), $BAR_CHAR);}
        
        # Si on est à 100%
        if($nbChar -eq $BAR_SIZE)
        {
            $toDisp += $BAR_CHAR
        }
        else # on n'est pas encore à 100%
        {
            # Ajout du caractère final et d'espaces jusqu'à arriver à la barre de la bonne taille
            $toDisp += $BAR_END_CHAR
            $toDisp = $toDisp.padRight($BAR_SIZE-$nbChar+$toDisp.Length, " ")
            
        }
        
        $toDisp += "] $percent%"
        
        $toDisp = $toDisp.padRight(20+$toDisp.Length, " ")
        
        Write-Host "`r$toDisp" -NoNewline
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Enlève les SID incorrects sur les fichiers

        IN  : $filesAndSIDList        -> tableau avec la liste des fichiers et SID à enlever.
                                        Ex : \\path\to\file;SID-1-2-3-4:0xHEXA_MASK
    #>
    hidden [void] removeSIDsInFiles([array]$filesAndSIDList)
    {
    $failedFiles = @()
    # Si aucun SID à supprimer, on quitte 
    if($filesAndSIDList.Count -eq 0) 
    {
        return
    }

    $nbSIDRemoved = 0
    if($filesAndSIDList.Count -le 200){$dispEvery = 10;}else{$dispEvery = 100;}

    $this.dispProgress($nbSIDRemoved, $filesAndSIDList.Count, "Removing SIDs")

    # Parcours des SID à supprimer 
    foreach($SIDInfos in $filesAndSIDList)
    {

        $nbSIDRemoved++
        if( ($nbSIDRemoved % $dispEvery) -eq 0)
        {
        $this.dispProgress($nbSIDRemoved, $filesAndSIDList.Count, "Removing SIDs")
        }

        # Extraction du SID
        $SID = (((($SIDInfos.Split(";"))[1]).Split(":"))[0]).Trim()
    
        # Si pour une raison ou une autre le SID est vide, on continue avec le suivant
        if($SID -eq "") 
        {
            continue
        }
        # Extraction du nom de fichier
        $filename = $SIDInfos.Split(";")[0]
    
        # Si le fichier n'existe plus, on passe au suivant 
        if(!(Test-Path $filename)){ continue }

        $argsDeny = ""
        # Si c'est un SID "DENY", 
        if($SID.StartsWith("DENY!"))
        {
            # Il y va y avoir un argument en plus à passer pour dire que c'est un DENY que l'on veut enlever
            $argsDeny = " /REMOVEDENY "
            # Suppression du "Deny" s'il y en a un...
            SID = $SID.Replace("DENY!", "");
        }
    
        $O = New-Object System.Security.Principal.SecurityIdentifier($SID)
        # Tentative de recherche du nom d'utilisateur correspondant au SID
        try
        {
            $username = $O.Translate([System.Security.Principal.NTAccount]).Value
        }
        catch # Si on ne trouve pas, on dit qu'il est indéfini
        {
            $username = "UNDEFINED!"
        }
    
        # Ecriture dans le fichier log
        $this.writetolog("Removing SID $SID for user $username on $filename... ")
        # Création ligne de commande pour virer le SID des ACLs.
        # !! On ne peut pas traiter les chemins plus long que 260 caractères. Le fait d'ajouter \\?\ devant le chemin empêche fileacl 
        # de fonctionner correctement, il sort avec une erreur :
        # GetVolumeInformation error! (rc=3) The system cannot find the path specified.

        try
        {
        # Suppression du SID courant dans les fichiers 
        $this.runFileACL("`"$filename`" /R $SID $argsDeny /protect /force /files")
        }
        catch
        {
            $failedFiles += $filename
        }
    
    }
    
    $this.dispProgress($filesAndSIDList.Count, $filesAndSIDList.Count, "Removing SIDs")
    if($failedFiles.count -gt 0)
    {
        $this.writeToLogAndHost(("SID removal failed for {0} files: `n{1}" -f $failedFiles.count, ($failedFiles -join "`n")))
    }
    }

    
    <#
        -------------------------------------------------------------------------------------
        BUT : Réapplique les ACLs correctes pour un utilisateur

        IN  : $userUNCDirectory    -> le chemin UNC jusqu'au dossier où reconstruire
        IN  : $userAtDomain        -> le nom du user sous la forme DOMAIN\username
        IN  : $skipSubFolders      -> (optionnel) $true|$false (si pas passé -> $false)
                                        Pour dire s'il faut skip la reconstruction des sous-dossiers
        IN  : $addExecRight        -> (optionnel) $true|$false (si pas passé -> $false)
                                        Pour dire qu'il faut ajouter le droit "Exec" pour les fichiers 
                                        pour le dossier défini par $userUNCDirectory

        REMARQUE : Durant la reconstrucion, même si on applique les ACLs des dossiers et des
                    fichiers pile en même temps, il va y avoir une toute petite perte d'accès
                    mais pendant un temps très faible
    #>
    hidden [void] reApplyCorrectACLs([string]$userUNCDirectory, [string]$userAtDomain, [string]$userSID, [bool]$skipSubFolders, [bool]$addExecRight)
    {
        # -- Ajout des droits

        # Rebuild des fichiers 
        
        # S'il faut ajouter le droit d'éxécution
        if($addExecRight)
        {
            $fileRights = ":RrRaRepWwAWaWePDDcOX:F"
        }
        else # Il ne faut pas ajouter le droit d'exécution
        {
            $fileRights = ":RrRaRepWwAWaWePDDcO:F"
        }
        
        # S'il faut skip les sous-dossiers (dans le cas où on a créé un sous-dossier où on a mis les droits d'exécution et on n'a pas envie de les écraser 
        # en reconstruisant les droits du dossier parent)
        if($skipSubFolders)
        {
            $subParam = ""
        }
        else # Il ne faut pas skip les sous-dossiers
        {
            $subParam = "/sub"
        }
        $this.writeToLogAndHost("Rebuilding files permissions for $userAtDomain... ")
        $this.runFileACL([string]::Concat($userUNCDirectory, " /O ", $userSID, " /S ", $userSID ," ", $fileRights, " /force /files ", $subParam))
        
        # Rebuild des dossiers 
        $this.writeToLogAndHost("Rebuilding folders permissions for $userAtDomain... ")
        $this.runFileACL([string]::Concat($userUNCDirectory, " /O ", $userSID, " /G ", $userSID, ":RrRaRepWwAWaWePXDDcO:FSF /sub /force"))
        
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Ajoute le droit 'execute' à une liste de fichier pour le user passé

        IN  : $fileList			-> tableau avec la liste des fichiers pour lesquels ajouter les droits
        IN  : $forUserAtDomain	-> L'utilisateur pour lequel ajouter les droits
    #>
    hidden [void] addExecRightToFiles([array]$fileList, [string]$forUserAtDomain)
    {
    $nbFilesModified = 0
    $failedFiles = @()
    
    if($fileList.Count -le 200){ $dispEvery = 10;} else { $dispEvery = 100; }
    
    $this.dispProgress($nbFilesModified, $fileList.Count, "Modifying files")
    
    # Parcours des fichiers à modifier 
    foreach ($file in $fileList)
    {
        $nbFilesModified++
        if( ($nbFilesModified % $dispEvery) -eq 0)
        {
            $this.dispProgress($nbFilesModified, $fileList.Count, "Modifying files")
        }
        
        # Si le fichier n'existe pas, on le skip.
        if(!(Test-Path $file)){ continue; }
    
        $this.writeToLog("Adding 'exec' right for $file to $forUserAtDomain")
        try
        {
            # Ajout du droit 'execute' pour le fichier et l'utilisateur 
            $this.runFileACL([string]::Concat("$file /S ", $forUserAtDomain, ":RrRaRepWwAWaWePDDcOX /force /files"))
        }
        catch
        {
            $failedFiles += $file
        }
        
        
    }
    
    $this.dispProgress($fileList.Count, $fileList.Count, "Modifying files")
    if($failedFiles.count -gt 0)
    {
        $this.writeToLogAndHost(("Adding exec right failed for {0} files: `n{1}" -f $failedFiles.count, ($failedFiles -join "`n")))
    }
        
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Affiche l'étape courante pour l'avancement
        
        IN  : $stepNo       -> No de l'étape courante
        IN  : $nbSteps      -> Nombre d'étapes
        IN  : $description  -> description de l'étape courante
    #>
    hidden [void] displayStep([int]$stepNo, [int]$nbSteps, [string]$description)
    {
        $message = ([string]::Concat("[",$stepNo,"/", $nbSteps,"] ", $description))
        $this.writeToLogAndHost($message)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Donne les droits aux admins pour un utilisateur donné sur un serveur donné
        
        IN  : $server       -> nom du serveur
        IN  : $username     -> username     
    #>
    [void] grantAdminAccess([string]$server, [string]$username)
    {
    $this.initUserLogFile($server, $username)

    $userDir = $this.nameGeneratorMyNAS.getUserUNCPath($server, $username)

    if(!(Test-Path -Path $userDir))
    {
        Throw ("Path to grant admin to doesn't exists ({0})" -f $userDir)
    }

        $this.writeToLogAndHost("Adding rights to admin for server $server and username $username... ")

        $this.runFileACL("$userDir /G administrators:FSFF /sub /protect /force /files") | Out-Null

    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Supprime les droits aux admins pour un utilisateur donné sur un serveur donné
        
        IN  : $server       -> nom du serveur
        IN  : $username     -> username     
    #>
    [void] removeAdminAccess([string]$server, [string]$username)
    {
    $this.initUserLogFile($server, $username)

    $userDir = $this.nameGeneratorMyNAS.getUserUNCPath($server, $username)

    if(!(Test-Path -Path $userDir))
    {
        Throw ("Path to remove admin from doesn't exists ({0})" -f $userDir)
    }

        $this.writeToLogAndHost("")
        $this.writeToLogAndHost("Removing rights to admin for server $server and username $username... ")

        $this.runFileACL("$userDir /R administrators /sub /protect /force /files") | Out-Null

        $this.writeToLogAndHost("Done")
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Reconstruit les droits sur un dossier donné
        
        IN  : $server              -> nom du serveur
        IN  : $username            -> username     
        IN  : $rebuildForUsername  -> Nom d'utilisateur pour lequel reconstruire les droits
        IN  : $execFolder          -> (optionnel) Nom du dossier qui devra avoir le droit "exécutable"
                                        Ce paramètre permet de faire en sorte de s'assurer que le dossier en question
                                        aura effectivement les droits d'exécutions pour les fichiers qui seront créés
                                        dedans. Il n'est nécessaire qu'à la création initiale du dossier utilisateur,
                                        par la suite, lors d'une potentielle reconstruction des droits, il sera repéré
                                        comme ayant le droit d'exécution et ce droit sera réappliqué.
    #>
    [void] rebuildUserRights([string]$server, [string]$username, [string]$rebuildForUsername)
    {
        $this.rebuildUserRights($server, $username, $rebuildForUsername, "")
    }
    [void] rebuildUserRights([string]$server, [string]$username, [string]$rebuildForUsername, [string]$execFolder)
    {
    $this.initUserLogFile($server, $username)

    $userUNCDirectory = $this.nameGeneratorMyNAS.getUserUNCPath($server, $username)

    if(!(Test-Path -Path $userUNCDirectory))
    {
        Throw ("Path to rebuild doesn't exists ({0})" -f $userUNCDirectory)
    }

        $this.writeToLogAndHost("")

        $nbSteps = 7
        # * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
        # Etape 1 : Recherche infos utilisateur
        $this.displayStep(1, $nbSteps, "Getting infos for user $rebuildForUsername...")
        $userInfos = $this.searchDomainUserInfos($rebuildForUsername)
        # Si user pas trouvé, on quitte
        if($null -eq $userInfos)
        {
            return
        }
        
        # # Enregistrement des valeurs retournées 
        $domainBackslashUser = [string]::Concat($userInfos.domainShortName.ToUpper() ,"\", $rebuildForUsername)
        $userAtDomain    = [string]::Concat($rebuildForUsername, "@", $userInfos.domainFullName)
        $this.writeToLogAndHost("Domain     : {0}" -f $userInfos.domainFullName)
        $this.writeToLogAndHost("Domain\User: {0}" -f $domainBackslashUser)
        $this.writeToLogAndHost("SID        : {0}" -f $userInfos.userSID)
        $this.writeToLogAndHost("User dir   : {0}" -f $userUNCDirectory)
        
        
        # # * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
        # Etape 2 : Ajouter les droits pour les admins
        $this.displayStep(2, $nbSteps, "Adding rights to admins...")
        $this.grantAdminAccess($server, $username)
        
        
        # # * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
        # Etape 3 : Récupération des fichiers qui sont exécutables pour le user ainsi que la liste des tous les SID se trouvant dans les ACLs
        $this.displayStep(3, $nbSteps, "Searching executable files for $domainBackslashUser and all SID in the ACLs...")
        
        # # Recherche des fichiers/dossiers exécutables ainsi que de tous les SID présents 
        $execFilesAndSID = $this.searchExecFilesForUserAndAllSID($userUNCDirectory, $domainBackslashUser, @("S-1-5-32-544", $userInfos.userSID))
        
        # Liste des fichiers avec l'attribut 'exec'
        $this.writeToLogAndHost(("Executable files found: {0}" -f $execFilesAndSID.filesWithExec.Count))
        $this.writeToLogAndHost(("Incorrect SIDs found  : {0}" -f $execFilesAndSID.filesAndSID.Count))
        

        # # * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
        # Etape 4 : Suppression des ACLs pour les SID qui n'ont rien à faire là
        # S'il y a des SID à supprimer 
        $this.displayStep(4, $nbSteps, "Removing incorrec SID from ACLs...")
        
        # S'il y a des SID à enlever, 
        if($execFilesAndSID.filesAndSID.Count -gt 0)
        {
            $this.writeToLogAndHost(("Removing {0} SID from ACLs... " -f $execFilesAndSID.filesAndSID.Count))
            
            $this.removeSIDsInFiles($execFilesAndSID.filesAndSID)
            $this.writeToLogAndHost("Done")
        }
        else # Aucun SID à supprimer des ACLs
        {
            $this.writeToLogAndHost("No SID to remove from ACLs")
        }
        
        # # * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
        # Etape 5 : Réapplication des ACLs correctes pour le user
        # Reconstruction
        $this.displayStep(5, $nbSteps, "Reapplying correct ACLs...")
        
        # Si on a un dossier sur lequel mettre le droit "execute"
        if($execFolder -ne "")
        {
            $skipSubFolders = $true
            $userUNCDirectoryExec = "{0}\{1}" -f $userUNCDirectory, $execFolder
            $this.reApplyCorrectACLs($userUNCDirectoryExec, $userAtDomain, $userInfos.userSID, $skipSubFolders, $true)
        }
        else # On n'a pas de dossier avec les droits exécutables 
        {
            $skipSubFolders = $false
        }
        $this.reApplyCorrectACLs($userUNCDirectory, $userAtDomain, $userInfos.userSID, $skipSubFolders, $false)
        
        
        
        # # * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
        # Etape 6 : Remise en place des droits 'execute' sur les fichiers récupérés précédemment
        # S'il y a des fichiers auxquels ajouter le droit 'execute',
        $this.displayStep(6, $nbSteps, "Reapplying 'exec' right on files... ")
        
        # S'il y a des fichiers sur lesquels il faut remettre le droit "exec"
        if($execFilesAndSID.filesWithExec.Count -gt 0)
        {
            $this.writeToLogAndHost([string]::Concat("Reapplying 'exec' rights on ", $execFilesAndSID.filesWithExec.Count," files"))

            $this.addExecRightToFiles($execFilesAndSID.filesWithExec, $userAtDomain)
            
        }
        else # Il n'y a pas de fichiers avec le droit exec
        {
            $this.writeToLogAndHost("No files with exec rights to restore")
        }
        
        
        # # * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
        # Etape 7 : Suppression des droits pour les admins
        $this.displayStep(7, $nbSteps, "Removing admin rights...")
        $this.removeAdminAccess($server, $username)
        $this.writeToLogAndHost("Rebuild DONE!")
    }
}