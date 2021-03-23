<#
USAGES:
    xaas-nas-onboarding.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action genDataFile -volType col|app -dataFile <dataFile>
    xaas-nas-onboarding.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action import -volType col|app -dataFile <dataFile>
#>
<#
    BUT 		: Script permettant d'effectuer le onboarding des volumes NAS
                  

	DATE 	: Mars 2021
    AUTEUR 	: Lucien Chaboudez
    
#>
param([string]$targetEnv, 
      [string]$targetTenant,
      [string]$action,
      [string]$volType,
      [string]$dataFile)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

# Chargement des fichiers propres au NAS NetApp
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "NameGeneratorNAS.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal   = [ConfigReader]::New("config-global.json")
$configvRA      = [ConfigReader]::New("config-vra.json")
$configNAS      = [ConfigReader]::New("config-xaas-nas.json")
$configLdapAd   = [ConfigReader]::New("config-ldap-ad.json")



# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_GEN_DATA_FILE       = "genDataFile"
$ACTION_IMPORT              = "import"

$CSV_SEPARATOR = ";"


# -------------------------------------------- FONCTIONS ---------------------------------------------------


<# -----------------------------------------------------------
    Renvoie les infos d'une demande initiale de volume
#>
function getVolInitialRequest([SQLDB]$sqldb, [string]$volId)
{
    $request = "SELECT * FROM nas_req_fs WHERE nas_fs_id={0} AND action_desc_code='fs-user-new'" -f $volId
    $request = "SELECT * FROM action_log WHERE nas_fs_id={0} AND action_desc_code='fs-user-new'" -f $volId

    $conditions = @(
        "nas_req_fs.nas_req_fs_id=action_log.nas_req_fs_id",
        ("nas_req_fs.nas_fs_id={0}" -f $volId),
        "nas_req_fs.action_desc_code='fs-user-new'",
        "action_log.action_desc_code='fs-user-new'"
    )

    $request = "SELECT * FROM nas_req_fs, action_log WHERE {0}" -f ($conditions -join " AND ")

    return $sqldb.execute($request)
}


<# -----------------------------------------------------------
    Renvoie la liste des volumes qui doivent être onboardés
#>
function getVolToOnboard([SQLDB]$sqldb, [string]$volType)
{

    $volTypeIdList = switch($volType) 
    {
        "col"{ @(2,4,5)}
        "app"{ @(1) }
    }

    $tables = @(
        "nas_fs",
        "infra_vserver",
        "nas_service_type",
        "nas_fs_admin_mail",
        "managers_emails"
    )

    $conditions = @(
        # Joinntures
        "nas_fs.infra_vserver_id = infra_vserver.infra_vserver_id",
        "nas_fs.nas_fs_svc_type_id = nas_service_type.nas_svc_type_id",
        "nas_fs.nas_fs_date_delete_asked IS NULL",
        "nas_fs.nas_fs_id=nas_fs_admin_mail.nas_fs_id",
        "nas_fs.nas_fs_faculty = managers_emails.faculty",

        # Conditions de recherche
        ("nas_fs_svc_type_id IN ({0})" -f ($volTypeIdList -join ",")),
        "nas_fs.nas_fs_name NOT IN (SELECT vol_name FROM nas2020_onboarding)"
    )

    $columns = @(
        "nas_fs.*",
        "managers_emails.vserver_name_prefix",
        "nas_service_type.nas_svc_type_name",
        "infra_vserver.infra_vserver_name",
        "GROUP_CONCAT(nas_fs_admin_mail.nas_fs_admin_mail)AS mailList"
    )

    
    $request = ("SELECT {0} FROM {1} WHERE {2} GROUP BY nas_fs_admin_mail.nas_fs_id ORDER BY nas_fs_unit,infra_vserver_name,nas_fs_name " -f `
                ($columns -join ","), ($tables -join ","), ($conditions -join " AND "))

    return $sqldb.execute($request)
}


<# -----------------------------------------------------------
    Renvoie le nom d'une unité en fonction de son ID 
#>
function getUnitName([array]$params)
{
    return $ldap.getUnitInfos($params[0]).cn
}




<# -----------------------------------------------------------
    Renvoie le BG en fonction de son ID
#>
$global:BG_LIST = @()
function getTargetBG([array]$params)
{
    if($volType -eq "col")
    {
        # Si on n'a pas d'infos, on ne va pas chercher plus loin
        if($params[0] -eq [DBNull]::Value )
        {
            return ""
        }
        # On regarde dans le cache
        $bg = $global:BG_LIST | Where-Object { $_.id -eq $params[0]}

        # Si pas trouvé dans le cache
        if($null -eq $bg)
        {
            $vraBG = $vra.getBGByCustomId($params[0])

            if($null -eq $vraBG)
            {
                return ""
            }

            $bg = @{
                id = $params[0]
                name = $vraBG.name
            }

            $global:BG_LIST += $bg
        }

        return $bg.name
    }
    return ""
}


<# -----------------------------------------------------------
    Renvoie le type d'accès correct qui est utilisé pour le NAS
#>
function getAccessType([array]$params)
{

    if($params[0] -eq "nfsv3")
    {
        return "nfs3"
    }

    if($params[0] -eq "cifs-app")
    {
        return "cifs"
    }
    return $params[0]
}


<# -----------------------------------------------------------
    Renvoie la lettre d'une colonne en fonction du numéro (ne fonctionne que pour 26 colonnes)
#>
function getExcelColName([int]$colIndex)
{
    $offset = [byte][char]'A'

    return [char][byte] ($offset +$colIndex -1)
}

<# -----------------------------------------------------------
    Renvoie la bonne faculté à utiliser en fonction du mapping qui est défini
#>
function getRightFaculty([array]$params)
{
    $forFaculty = $params[0]

    $targetFaculty = switch($forFaculty)
    {
        "VPSI" { "VPO-SI" }
        "R" { "VPO-SI" }

        default { $forFaculty }
    }

    return $targetFaculty
}



# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new(@('xaas','nas', 'onboarding'), $global:LOGS_FOLDER, 30)
    
    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
    }
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                                                    ($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet pour se connecter aux clusters NetApp
    $netapp = [NetAppAPI]::new($configNAS.getConfigValue(@($targetEnv, "serverList")),
                                $configNAS.getConfigValue(@($targetEnv, "user")),
                                $configNAS.getConfigValue(@($targetEnv, "password")))


    $ldap = [EPFLLDAP]::new($configLdapAd.getConfigValue(@("user")), $configLdapAd.getConfigValue(@("password")))						                                 

    # Pour accéder à la base de données
	$sqldb = [SQLDB]::new([DBType]::MySQL,
                        $configNAS.getConfigValue(@("websiteDB", "host")),
                        $configNAS.getConfigValue(@("websiteDB", "dbName")),
                        $configNAS.getConfigValue(@("websiteDB", "user")),
                        $configNAS.getConfigValue(@("websiteDB", "password")),
                        $configNAS.getConfigValue(@("websiteDB", "port")), $false)                                

    $logHistory.addLineAndDisplay("Connecting to vRA...")
    $vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
                            $targetTenant, 
                            $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
                            $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $netapp.activateDebug($logHistory)    
    }

    
    $cols = @(
        @("nas3VolName", "nas_fs_name"),
        @("nas3VServer", "infra_vserver_name"),
        @("accessType", @("getAccessType", "nas_fs_access_type_id")),
        @("Type", "nas_fs_type_id"),
        @("unitId", "nas_fs_unit"),
        @("unitName", @("getUnitName", "nas_fs_unit") ),
        @("Rattachement", "nas_fs_rattachement"),
        @("Faculty", @("getRightFaculty", "nas_fs_faculty")),
        @("WebDav", "nas_fs_webdav_access"),
        @("Comment", "nas_fs_comment"),
        @("Reason for req", "nas_fs_reason_for_request"),
        @("Mail List", "mailList"), 
        "volNo",
        "nas2020VolName",
        "Owner (user@intranet.epfl.ch)",
        @("targetBgName", @("getTargetBG", "nas_fs_unit")),
        "onboard Date")
        

    $colCounter = 1
    $colNas3VolName     = $colCounter++
    $colNas3vServer     = $colCounter++
    $colAccessType      = $colCounter++
    $colType            = $colCounter++
    $colUnitId          = $colCounter++
    $colUnitName        = $colCounter++
    $colRattachement    = $colCounter++
    $colFaculty         = $colCounter++
    $colWebDav          = $colCounter++
    $colComment         = $colCounter++
    $colReasonForRequest= $colCounter++
    $colMailList        = $colCounter++
    $colVolNo           = $colCounter++
    $colNas2020VolName  = $colCounter++
    $colOwner           = $colCounter++
    $colTargetBGName    = $colCounter++
    $colOnboardDate     = $colCounter++
    
    $excel = New-Object -ComObject excel.application 
    $excel.visible = $true

    #$dataFile = ([IO.Path]::Combine("$PSScriptRoot", $dataFile))
    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau Volume 
        $ACTION_GEN_DATA_FILE 
        {
            Write-Host -NoNewLine "Getting volume list... "
            $volList = getVolToOnboard -sqldb $sqldb -volType $volType
            Write-Host "done" -foregroundColor:DarkGreen


            if(Test-Path $dataFile)
            {
                Remove-Item $dataFile -Force
            }

            $workbook = $excel.Workbooks.Add()

            $excelSheet= $workbook.Worksheets.Item(1) 
            $excelSheet.Name = 'Volume list'
            $usedRange = $excelSheet.UsedRange
            $usedRange.EntireColumn.AutoFit()| Out-Null

            $colNo = 1
            $cols | ForEach-Object{
                $excelSheet.Cells.Item(1, $colNo) = @($_)[0]
                $colNo++
            }

            Write-Host -NoNewLine ("Extracting data ({0} volumes)" -f $volList.count)
            $progressStep = 10
            $lineNo = 2
            # Parcours des volumes récupérés
            Foreach($vol in $volList)
            {
                if(($lineNo % $progressStep) -eq 0)
                {
                    Write-Host $lineNo -NoNewLine
                }
                else
                {
                    Write-Host "." -NoNewLine
                }

                
                $colNo = 1
                $cols | ForEach-Object {
                    
                    $tag, $dbCol = $_

                    # Si pas de nom de champ ou de fonction
                    if($null -eq $dbCol)
                    {

                        switch($colNo)
                        {
                            # - Volume Name
                            $colNas2020VolName
                            {
                                # Formule pour calculer
                                $suffix = ""
                                if($vol.nas_fs_access_type_id -eq "nfsv3")
                                {
                                    $suffix = '&"_nfs"'
                                }
                                $formula = Switch($volType)
                                {
                                    "col" { '="u"&{1}{0}&"_"&LOWER(SUBSTITUTE({2}{0},"-",""))&"_"&LOWER(SUBSTITUTE({3}{0},"-",""))&"_"&{4}{0}&"_files"{5}' -f `
                                            $lineNo, 
                                            (getExcelColName -colIndex $colUnitId), 
                                            (getExcelColName -colIndex $colFaculty),
                                            (getExcelColName -colIndex $colUnitName),
                                            (getExcelColName -colIndex $colVolNo),
                                            $suffix }
                                    "app" { Throw "Not handled"}
                                }

                                $excelSheet.Cells.Item($lineNo, $colNo).Formula = $formula
                            }


                            # - Owner
                            $colOwner
                            {
                                # Recherche de la requête "initiale"
                                $reqInfos = getVolInitialRequest -sqldb $sqldb -volId $vol.nas_fs_id

                                if($null -ne $reqInfos)
                                {
                                    # Suppression d'une éventuelle première partie avec un ,
                                    $userFullName = $reqInfos.act_log_user_name -replace ".*?," , "" 
                                    
                                    $person = $ldap.getPersonInfos($userFullName)

                                    # Si pas trouvé dans LDAP
                                    if($null -ne $person)
                                    {
                                        $owner = "{0}@intranet.epfl.ch" -f ($person.uid | Where-Object { $_ -notlike "*@*"})
                                    }
                                    else
                                    {
                                        $owner = "!!!!!!!!!{0}" -f $userFullName
                                        $excelSheet.Cells.Item($lineNo, $colNo).Interior.ColorIndex = 3 # rouge
                                    }
                                    

                                    $excelSheet.Cells.Item($lineNo, $colNo) = $owner
                                }
                            }
                        }
                        

                    }
                    else # C'est un nom de champ ou de fonction
                    {
                        
                        # Si on a des infos sur une fonction à utiliser
                        if($dbCol -is [System.Array])
                        {
                            $funcName, $paramNameList = $dbCol
                            $paramValueList = @()
                            Foreach($param in $paramNameList)
                            {
                                $paramValueList += $vol.$param
                            }
                            $expression = '$val = {0}' -f $funcName
                            if($paramValueList.count -gt 0)
                            {
                                $expression = '{0} -params $paramValueList' -f $expression
                            }
                            Invoke-expression $expression

                        }
                        else # Si nom de champ
                        {
                            $val = $vol.$dbCol
                        }

                        $excelSheet.Cells.Item($lineNo, $colNo) = $val
                        

                    } 

                    $colNo++
                }# Fin boucle de parcours des colonnes de la ligne courante 

                $lineNo++
            }# Fin boucle de parcours des volumes récupérés

            # On fige le header
            $excel.Rows.Item("2:2").Select() | Out-Null
            $excel.ActiveWindow.FreezePanes = $true

            Write-Host "done" -foregroundColor:DarkGreen

            $workbook.SaveAs($dataFile)
            $excel.Quit()

            Write-Host ("Output can be found in '{0}' file" -f $dataFile)
        }


        # -- Importation depuis un fichier de données
        $ACTION_IMPORT
        {
            
            $catalogItemName = "Raw Onboard Volume"
        
            # Test de l'existence du fichier de données
            if(!(Test-Path $dataFile))
            {
                Throw ("Data file '{0}' not found !" -f $dataFile)
            }

            # Récupération de l'item de catalogue correspondant au type du volume à importer
            $catalogItem = $vra.getCatalogItem($catalogItemName)

            if($null -eq $catalogItem)
            {
                Throw ("Catalog Item '{0}' not found on {1}::{2}" -f $catalogItemName, $targetEnv.toUpper(), $targetTenant)
            }

            $workbook = $excel.Workbooks.Open($dataFile)
            $excelSheet= $workbook.Worksheets.Item(1) 

            # On commence juste par check l'unicité des noms de volumes
            Write-Host "Checking volume name unicity... " -NoNewLine
            $volList = @()
            for($lineNo=2 ; $lineNo -le ($excelSheet.UsedRange.Rows).count; $lineNo++)
            {
                $volName = $excelSheet.Cells.Item($lineNo, $colNas2020VolName).text
                if($volList -contains $volName)
                {
                    Throw ("Duplicate volume name found: {0}" -f $volName)
                }
                $volList += $volName
            }
            Write-Host "done" -foregroundColor:DarkGreen


            Write-Host "Doing job... "
            # Parcours des éléments du fichier Excel
            for($lineNo=2 ; $lineNo -le ($excelSheet.UsedRange.Rows).count; $lineNo++)
            {
                $volName = $excelSheet.Cells.Item($lineNo, $colNas2020VolName).text
                Write-Host ("Volume '{0}'..." -f $volName)

                $onboardDate = $excelSheet.Cells.Item($lineNo, $colOnboardDate).text
                if($onboardDate -ne "")
                {
                    Write-Host ("> Already onboarded ({0}), skipping" -f $onboardDate)
                    continue
                }

                # Check de la validité des données entrées dans le fichier Excel
                for($colNo = $colVolNo; $colNo -lt $colOnboardDate; $colNo++ )
                {
                    if($excelSheet.Cells.Item($lineNo, $colNo).text -eq "")
                    {
                        Throw ("Empty value found on line {0} and column no {1}" -f $lineNo, $colNo)
                    }
                }

                # -- Business Group
                $bgName = $excelSheet.Cells.Item($lineNo, $colTargetBGName).text
                Write-Host ("> Getting BG '{0}'..." -f $bgName)

                $bg = $vra.getBG($bgName)

                if($null -eq $bg)
                {
                    Throw ("Incorrect BG ({0}) given for volume ({1}). Check Excel file on line {2}" -f $bgName, $volName, $lineNo)
                }

                # -- Volume
                Write-Host ("> Getting Volume '{0}'..." -f $volName)
                $netappVol = $netapp.getVolumeByName($volName)

                if($null -eq $netappVol)
                {
                    Throw ("Incorrect volume name ({0}) given. Check Excel file on line {1}" -f $volName, $lineNo)
                }

                
                $owner = $excelSheet.Cells.Item($lineNo, $colOwner).text

                Write-Host ("> Getting request template...")
                $template = $vra.getCatalogItemRequestTemplate($catalogItem, $bg, $owner)

                if($null -eq $template)
                {
                    Throw "Template not found!"
                }

                # Remplissage du template
                #$template.description = $excelSheet.Cells.Item($lineNo, $colComment).text
                #$template.reasons = $excelSheet.Cells.Item($lineNo, $colReasonForRequest).text

                $template.data.access = $excelSheet.Cells.Item($lineNo, $colAccessType).text
                $template.data.bgName = $bgName
                $template.data.deploymentTag = $excelSheet.Cells.Item($lineNo, $colType).text
                $template.data.notificationMail = $excelSheet.Cells.Item($lineNo, $colMailList).text
                $template.data.reasonsForRequest = $excelSheet.Cells.Item($lineNo, $colReasonForRequest).text
                $template.data.requestor = $owner
                $template.data.svm = $netappVol.svm.name
                $template.data.targetTenant = $targetTenant

                $template.data.volId = $netappVol.uuid
                $template.data.volName = $volName
                $template.data.volType = $volType
                $template.data.webdavAccess = ($excelSheet.Cells.Item($lineNo, $colWebDav).text -eq "1")

                Write-Host "> Doing request" -NoNewLine
                $res = $vra.doCatalogItemRequest($catalogItem, $bg, $owner, $template)

                do
                {
                    Start-Sleep -Seconds 5
                    Write-Host "." -NoNewLine
                    $request = $vra.getCatalogItemRequest($res.id)
                }
                while($request.state -eq "RUNNING")
                
                Write-Host " done" -foregroundColor:DarkGreen


                # Mise à jour de la date d'onboarding et sauvegarde du fichier
                Write-Host "> Saving onboard date..."
                $excelSheet.Cells.Item($lineNo, $colOnboardDate) = (Get-Date -Format "yyyy-MM-dd H:m:s")
                $workbook.SaveAs($dataFile)
                
            }# FIN Parcours des lignes du fichier Excel

            
            
            if($null -ne $excel)
            {
                $excel.Quit()
            }
            
        }# FIN ACTION IMPORT

        

    }


}
catch
{

    # Récupération des infos
    $errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace

    if($null -ne $excel)
    {
        $excel.Quit()
    }
    
    Write-Host ("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace) -foregroundColor:DarkRed

}

if($null -ne $vra)
{
    $vra.disconnect()
}
                                                