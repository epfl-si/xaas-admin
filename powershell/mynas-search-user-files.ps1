<#
USAGES:
	mynas-search-user-files.ps1 -sciperList <sciperList>
#>
<# --------------------------------------------------------------------------------
 BUT : Recherche les fichiers/dossiers appartenant à un utilistaeur MyNAS.
       Comme il n'existe pas de mécanisme sur NetApp pour avoir la liste des fichiers 
       d'un utilisateur donné à partir de ses informations de quota, ce script a été 
       développé. Il emploie l'utilitaire "fileacl" et liste les permissions de tous
       les fichiers/dossiers du volume sur lequel l'utilisateur se trouve. Une 
       recherche est ensuite effectuée avec le SID de l'utilisateur pour retrouver ce
       qui lui appartient sur le volume.
       En moyenne, le script permet de traiter 250'000 fichiers/dossiers par heure,
       ce qui représente quand même un temps de recherche assez conséquent!
 
 PREREQUIS : 1. Autoriser les scripts powershell à s'exécuter sans signature
                Set-ExecutionPolicy Unrestricted
             3. S'assurer que l'exécutable "fileacl.exe" soit dans le dossier "/bin/"
                Celui-ci peut être trouvé ici : http://www.gbordier.com/gbtools/fileacl.asp 
             4. L'utilisateur employé pour exécuter le script doit se trouver dans le groupe
                "Backup Operators" du serveur CIFS sur lequel la recherche est effectuée. Ceci
                est nécessaire afin de pouvoir avoir les droits nécessaires pour lister les 
                permissions des fichiers/dossiers.
 
 PARAMETRES :
       Ce script peut prendre 1 ou plusieurs sciper en paramètre. Si plusieurs sont passés,
       ils doivent impérativement se trouver sur le même vServer. Un contrôle est effectué
       à ce sujet. La recherche de plusieurs scipers en même temps permet de gagner du temps.
       S'il faut chercher les fichiers/dossiers de scipers se trouvant sur plusieurs vServers
       différents, il est conseillé de plutôt exécuter le script plusieurs fois en parallèle.
 
 REMARQUE : 
      Au vu du temps d'exécution du script, afin d'éviter de "monopolister" la machine "sanas-mon-2",
      il est plutôt recommandé de copier le nécessaire en local sur votre machine et de faire
      un "run as" d'une console PowerShell avec votre utilistaeur  "ditex-manage-XX". 
 
 
 AUTEUR : Lucien Chaboudez
 DATE	  : 15.07.2016
----------------------------------------------------------------------------------- #>

# En paramètre, il faut passer le sciper de l'utilisateur dont on veut trouver les fichiers/dossiers
param([string]$sciperList)


# Inclusion des constantes
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func-netapp.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "NameGeneratorMyNAS.inc.ps1"))


<#
	-------------------------------------------------------------------------------------
   BUT : Renvoie des informations sur un utilisateur

   IN  : $sciper	-> Sciper de l'utilisateur dont on veut les infos

   RET : Tableau avec:
         - username
         - sciper
	#>
function searchUserSID([string]$sciper)
{
   $user = Get-ADUser -LDAPFilter ("(company={0})" -f $sciper)

   if($null -eq $user)
   {
      return $false
   }

   return $user.SID.toString()
}


# ----------------------------------------------------------------------------------------------------------
# ---------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------

. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

# Création du nécessaire pour générer les noms
$nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()

# Si on a plus d'un sciper, 
$sidArray = @()
$serverPath = $null
# Parcours des Sciper passés
foreach($sciper in $sciperList.split(":"))
{
   # Si on n'a pas encore initialisé le chemin 
   if($null -eq $serverPath)
   {
      $serverPath = $nameGeneratorMyNAS.getServerUNCPath($sciper)
   }
   else # On a déjà initialisé le chemin 
   {
      # Si le chemin pour le sciper courant est différent, 
      if($serverPath -ne $nameGeneratorMyNAS.getServerUNCPath($sciper))
      {
         Throw "Error! given sciper list are not on same vServer"
         exit 1
      }
   }# FIN SI on a déjà initialisé le chemin 
   
   # Recherche du SID + gestion des erreurs 
   if( ($sciperSID = searchUserSID -sciper $sciper) -eq $false)
   {
      Throw ("Error! SID not found for Sciper ({0})" -f $sciper)
      exit 1
   }
   
   # Recherche du SID et ajout au tableau des conditions 
   $sidArray += (";OWNER={0}" -f $sciperSID)
   
}# FIN BOUCLE parcours des sciper passés

Write-Host ("Searching file for SCIPER(s) : {0}" -f $sciperList)

# Recherche du chemin jusqu'au serveur 
Write-Host ("Server path               :  {0}" -f $serverPath)
Write-Host ""

# ----- Création du process pour exécuter Fileacl 
$processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
$processStartInfo.FileName = "cmd.exe"
$processStartInfo.WorkingDirectory = $global:BINARY_FOLDER
$processStartInfo.UseShellExecute = $false
$processStartInfo.CreateNoWindow = $false
$processStartInfo.RedirectStandardOutput = $true
$processStartInfo.Arguments = (' /C fileacl.exe {0} /OWNER /FILES /RAW /SUB | findstr.exe "{1}"' -f $serverPath, ($sidArray -join " "))

# Récupération de l'heure de départ
$startTime = Get-Date

Write-Host "Searching files (this can take a looong time! coffee?)... " -NoNewline
$fileSearchProcess = [System.Diagnostics.Process]::Start($processStartInfo)
$fileList = $fileSearchProcess.StandardOutput.ReadToEnd()
 
$fileSearchProcess.WaitForExit()

# Récupération de l'heure après recherche 
$searchTime = Get-Date
Write-Host ("Search duration: {0}" -f (New-TimeSpan -Start $startTime -End $searchTime).ToString())


# S'il y a des fichier (donc des fichiers trouvés, )
if($null -ne $fileList)
{
   $fileList = $fileList.Split("`n", [stringSplitOptions]::RemoveEmptyEntries)
  
   Write-Host "Extracting folder/filenames... " -NoNewline
   
   # Génération du nom de fichier de sortie 
   $OUTPUT_FILE_LIST = Join-Path $global:MYNAS_RESULTS_FOLDER ("{0}.txt" -f $sciper)
   
   # Effacement du fichier s'il existait déjà 
   delOutputFilesIfExists -outputFileList $OUTPUT_FILE_LIST
   
   # Extraction des infos, on met tous les noms de fichiers dans un dossier
   # infos sous la forme : "M:\filemon.exe;S-1-5-21-57989841-436374069-839522115-19799"
   $fileList | ForEach-Object { ($_.Split(";"))[0]} | Where-Object { $_.Trim() -ne ""} | Out-File -FilePath $OUTPUT_FILE_LIST -Encoding default

   # Récupération de l'heure de fin de l'extraction et affichage 
   Write-Host ("Total duration: {0}" -f (New-TimeSpan -Start $searchTime -End (Get-Date)).ToString())
   
   Write-Host ("Result : {0} file(s) found" -f $fileList.Count)
   
   Write-Host "File/folder list can be found in file:"
   Write-host "$OUTPUT_FILE_LIST"
}
else # Aucun fichier trouvé
{
   Write-Host ("No folder/file found for user with SCIPER {0}" -f $sciper)
}
