<# BUT : Contient des fonctions qui sont utilisées par beaucoup de scripts PowerShell différents.
       Elles ont été regroupées dans un seul et même fichier afin d'éviter les copier-coller dans
       chaque script les nécessitant.

   AUTEUR : Lucien Chaboudez
   DATE   : 21.07.2014 

   UTILISATION : Il suffit d'ajouter une ligne comme ceci au début du script qui a besoin des fonctions :
   . "<pathToScript>func.inc.ps1"
   
 #>


# ---------------- FONCTIONS ---------------


# ------------------------------------------------------------------------

<# 
   BUT : Contrôle l'environnement pour être sûr que le script puisse s'exécuter correctement
#>
function checkEnvironment
{

   $pscpFile = ([IO.Path]::Combine($global:BINARY_FOLDER, "pscp.exe"))
   
   if(!(Test-Path $global:MYNAS_SSH_KEY))
   {
      Write-Host "Error! file $global:MYNAS_SSH_KEY doesn't exists" -ForegroundColor Red
      exit 1
   }
   
   # Test de la présence du fichier "EXE" pour envoyer les fichiers par SSH
   if(!(Test-Path $pscpFile))
   {
      Write-Host "Error! file '$pscpFile' not found" -ForegroundColor Red
      exit 1
   }
   
}


# ------------------------------------------------------------------------

# BUT : Permet de savoir combien d'éléments il y a dans l'objet passé en paramètre. On a besoin
#       d'avoir une fonction comme celle-ci car les CmdLets NetApp peuvent renvoyer soir
#       - un tableau d'objets
#       - un objet seul
#       - $null si rien n'est trouvé
function getNBElemInObject
{
   param([Object] $inObject)
   
   # Si rien trouvé
   if($null -eq $inObject)
   {  
      return 0
   }
   
   # Si c'est un tableau qui est renvoyé
   if($inObject -is [System.Array])
   { 
      return $inObject.count
   }
   
   return 1
}


# --------------------------------------------------------------------------------

<# 
   BUT : Renvoie l'UNC utilisée pour accéder au dossier d'un user
 
   IN  : $server      -> le nom du serveur
   IN  : $username    -> le nom de l'utilisateur
   
   MODIFS :
   17.08.2018 - LC - Génération d'exception si erreur

#>
function getUserUNCPath {

   param([string]$server, [string]$username)
   
   # Check des paramètres 
   if($server -eq "") { Throw "Error in getUserUNCPath: missing parameter server" }
   if($username -eq "") { Throw "Error in getUserUNCPath: missing parameter username" }
   
   #return [string]::Concat("\\", $server, ".epfl.ch\dit-",$server,"-t1\data\", $username);
   return [string]::Concat("\\", $server, ".epfl.ch\data\", $username);
   
}


# ------------------------------------------------------------------------

<# 
   BUT : Envoie un fichier sur le serveur web (ditex-web)

   IN  : $fileToPush    -> le fichier à envoyer
   IN  : $targetFolder  -> le dossier dans lequel mettre le fichier
                           
   REMARQUE:
   Attention de bien faire en sorte que la clef (rsa2 key fingerprint) identifiant le
   serveur cible se trouve bien dans le cache de l'utilisateur employé pour faire le
   "pscp". Lancer le script à la main depuis une CMDLINE avec l'utilisateur adéquat
   afin d'ajouter l'id au cache local.
#>
function pushFile
{
   param($fileToPush, $targetFolder)
   
   
   # Si le fichier à envoyer existe bien, 
   if(Test-Path -Path $fileToPush)
   {
      
      $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
      $processStartInfo.FileName = Join-Path $global:BINARY_FOLDER "pscp.exe"
      $processStartInfo.UseShellExecute = $false
      $processStartInfo.CreateNoWindow = $false
      $processStartInfo.RedirectStandardOutput = $false

      $processStartInfo.Arguments =  (' -i "{0}" "{1}" {2}@ditex-web.epfl.ch:{3}' -f $global:MYNAS_SSH_KEY, $fileToPush, $global:MYNAS_SSH_USER, $targetFolder)

      # Suppression du SID courant dans les fichiers
      $fileAclProcess = [System.Diagnostics.Process]::Start($processStartInfo)
      $fileAclProcess.WaitForExit()
      
      # Petite gestion d'erreur
      if($fileAclProcess.ExitCode -ne 0)
      {
         Write-Error $fileAclProcess.StandardError.ReadToEnd()
      }
      
   }
   
}


# ------------------------------------------------------------------------

# BUT : Supprime le fichier de sortie s'il existe déjà
# 
# IN  : $outputFileList     -> liste des fichiers de sortie à supprimer
function delOutputFilesIfExists
{
   param([array] $outputFileList)
   # Parcours des fichiers 
   foreach($outputFile in $outputFileList)
   {
      # Si existe, supression 
      if(Test-Path -Path $outputFile) { Remove-Item $outputFile}
   }
}


# ------------------------------------------------------------------------

# BUT : Récupère le contenu d'une page web et la renvoie dans un tableau,
#       une ligne par cellule de tableau
#
# IN  : url   -> URL à télécharger
function getWebPageLines 
{
   param([string]$url)
   
   $linesList = @();
   
   $webClient = New-Object Net.WebClient

   # Récupération de la page web
   $lines = $webClient.DownloadString($url)
   
   $webClient.Dispose()
   
   # parcours de la liste des lignes
   foreach ($line in $lines.split("`n"))
   {
      # Si c'est pas une ligne vide (Généralement, c'est la dernière ligne...)
      if($null -ne $line -and $line.Trim() -ne "")
      {
         $linesList += $line
      }
   }
   
   
   # Retour du $LinesList dans un tableau
   return $linesList
}


# ------------------------------------------------------------------

<#
   BUT : Envoie un mail aux admins du service (NAS ou MyNAS vu que c'est la même adresse mail)
   
   IN  : $mailSubject   -> Le sujet du mail
   IN  : $mailMessage   -> Le contenu du message

   FIXME: Remplacer par l'envoi de mails fait dans XaaS
#>
function sendMailToAdmins
{
   param([string] $mailSubject, [string] $mailMessage)

   #SMTP server name
   $smtpServer = "mail.epfl.ch"

   #Creating a Mail object
   $msg = new-object Net.Mail.MailMessage

   #Creating SMTP server object
   $smtp = new-object Net.Mail.SmtpClient($smtpServer)

   #Email structure
   $msg.From = $global:FROM_MAIL
   $msg.ReplyTo = $global:ADMIN_MAIL
   $msg.To.Add($global:ADMIN_MAIL)
   
   
   $msg.subject = "$mailSubject"
   $msg.body = $mailMessage
   $msg.IsBodyHTML=$true
 
   #Sending email
   $smtp.Send($msg)

}

# ------------------------------------------------------------------

<#
   BUT : Transforme un tableau contenant des "string" dans un string multi-lignes, 
         avec une ligne par case de tableau.
         
   IN  : $strArray      -> Tableau contenant les strings
   IN  : $lineSeparator -> (optionnel) Séparateur de lignes. Par défaut `n
   
   RET : String avec les lignes
   
   MODIFS : 
   29.05.2015 - LC - Ajout du paramètre $lineSeparator
#>
function stringArrayToMultiLineString
{
   param([System.Array] $strArray, [string] $lineSeparator)
   
   if($null -eq $lineSeparator)
   {
      $lineSeparator = "`n"
   }
   
   return ($strArray -join $lineSeparator).Trim()
}









