
param([string]$targetEnv)

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "CopernicAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "billing", "Billing.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "billing", "BillingS3Bucket.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "billing", "BillingNASVolume.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configBilling = [ConfigReader]::New("config-billing.json")
$configVra = [ConfigReader]::New("config-vra.json")


    # Pour accéder à la base de données
$sqldb = [SQLDB]::new([DBType]::MSSQL,
                    $configVra.getConfigValue(@($targetEnv, "db", "host")),
                    $configVra.getConfigValue(@($targetEnv, "db", "dbName")),
                    $configVra.getConfigValue(@($targetEnv, "db", "user")),
                    $configVra.getConfigValue(@($targetEnv, "db", "password")),
                    $configVra.getConfigValue(@($targetEnv, "db", "port")))



function execRequest([string]$request)
{
    Write-Host "$($request) " -NoNewline

    $res = $sqldb.execute($request)

    if($res -eq 1)
    {
        Write-Host -ForegroundColor:DarkGreen "Updated"
    }
    else
    {
        Write-Host -ForegroundColor:DarkYellow "No Update"
    }
}


$partList = @(
    "1 - Clean data",
    "2 - 'entityType' to 'entityCustomId'",
    "3 - update 'entityElement' value",
    "0 - Exit"
)

While($true)
{
    Write-Host ("Parts:`n{0}" -f ($partList -join "`n") )

    $part = Read-Host "Select Part"
    
    switch($part)
    {
    
        1 {
            $entityList =  $sqldb.execute("SELECT * FROM dbo.BillingEntity")
    
            ForEach($entity in $entityList)
            {
                $id, $name = $entity.entityElement.split(" ")
                $name = $name -join " "
    
                $duplicates = $sqldb.execute("SELECT * FROM dbo.BillingEntity WHERE entityElement LIKE '$($id) %' ORDER BY entityId ASC")
    
                # Si doublons
                if($duplicates.count -eq 2)
                {
                    $request = "UPDATE dbo.BillingEntity SET entityElement = '{0}', entityFinanceCenter = '{1}' WHERE entityId='{2}'" -f `
                         $duplicates[1].entityElement, $duplicates[1].entityFinanceCenter, $duplicates[0].entityId
                    execRequest -request $request
    
                    $request = "DELETE FROM dbo.BillingEntity WHERE entityId='{0}'" -f $duplicates[1].entityId
                    execRequest -request $request
                
                }
            }
        }
    
        2 {
            $dummy = Read-Host "Please add 'entityCustomId' (VARCHAR(50), NULL) column and hit ENTER: "
            $entityList = $sqldb.execute("SELECT * FROM dbo.BillingEntity")
    
            ForEach($entity in $entityList)
            {
                $id, $name = $entity.entityElement.split(" ")
                $name = $name -join " "
                $request = "UPDATE dbo.BillingEntity SET entityCustomId='$($id)' WHERE entityId='$($entity.entityId)'"
    
                execRequest -request $request
            }
    
            $dummy = Read-Host "Edit/add UNIQUE index (BillingEntityUniq) to use 'entityCustomId' column and hit Enter"
            
        }
    
        3 {
            $entityList = $sqldb.execute("SELECT * FROM dbo.BillingEntity")
    
            ForEach($entity in $entityList)
            {
                $id, $name = $entity.entityElement.split(" ")
                $name = $name -join " "
    
                $request = "UPDATE dbo.BillingEntity SET entityElement='$($name)' WHERE entityId='$($entity.entityId)'"
    
                execRequest -request $request
            }
    
            $dummy = Read-Host "Rename column 'entityElement' to 'entityName' and hit Enter"
    
        }
    
        0 {
            exit
        }
    
        default {
            Write-Host -ForegroundColor:DarkRed "Incorrect part!"
        }
    }
}
