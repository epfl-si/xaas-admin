<#
   	BUT : Contient une classe permetant de faire des requêtes dans le DNS

   	AUTEUR : Lucien Chaboudez
   	DATE   : Octobre 2020
	
#>
class EPFLDNS
{
    hidden [System.Management.Automation.PSCredential]$credentials
    hidden [string] $dnsServer
    hidden [string] $psEndpointServer


    <#
	-------------------------------------------------------------------------------------
		BUT : Constructeur de classe

        IN  : $dnsServer        -> Nom du serveur DNS
        IN  : $psEndpointServer -> Nom du serveur endpoint PowerShell que l'on va utiliser
                                    comme gateway. Doit se terminer par "intranet.epfl.ch"
		IN  : $username         -> Nom d'utilisateur pour faire la connexion
        IN  : $password         -> Mot de passe
        
        RET : Instance de la classe
	#>
    EPFLDNS([string]$dnsServer, [string]$psEndpointServer, [string]$username, [string]$password)
    {
        $this.credentials = New-Object System.Management.Automation.PSCredential -ArgumentList @($username, `
                                            (ConvertTo-SecureString -String $password -AsPlainText -Force))
        
        $this.dnsServer = $dnsServer
        $this.psEndpointServer = $psEndpointServer
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un enregistrement dans le DNS

		IN  : $name         -> Nom IP
		IN  : $ip           -> Adresse IP
		IN  : $zone         -> Nom de la Zone DNS
	#>
    [void] registerDNSIP([string]$name, [string]$ip, [string]$zone)
    {

        $scriptBlockContent =
        {
            # Récupération des paramètres
            $dnsServer, $dnsName, $dnsIP, $dnsZone = $args
            
            Add-DnsServerResourceRecordA -Computername $dnsServer -Name $dnsName -ZoneName $dnsZone -CreatePtr -IPv4Address $dnsIP

        }
        $errorVar = $null
        # On exécute la commande en local mais avec des credentials spécifiques
        Invoke-Command -ComputerName $this.psEndpointServer -ScriptBlock $scriptBlockContent -Authentication CredSSP -credential $this.credentials `
                        -ArgumentList @($this.dnsServer, $name, $ip, $zone)  -ErrorVariable errorVar -ErrorAction:SilentlyContinue

        # Gestion des erreurs
        if($errorVar.count -gt 0)
        {
            Throw ("Error adding DNS information: {0}" -f ($errorVar -join "`n"))
        }
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Supprime un enregistrement dans le DNS

		IN  : $name         -> Nom IP
        IN  : $zone         -> Nom de la Zone DNS
	#>
    [void] unregisterDNSName([string]$name, [string]$zone)
    {

        $scriptBlockContent =
        {
            # Récupération des paramètres
            $dnsServer, $dnsName, $dnsZone = $args

            $nodeARecordList = Get-DnsServerResourceRecord -ZoneName $dnsZone -ComputerName $dnsServer -Node $dnsName -RRType A -ErrorAction SilentlyContinue 
            
            if($null -ne $nodeARecordList)
            {
                # Si par hasard il y a plusieurs adresses IP, on les vire toutes
                $nodeARecordList | Foreach-Object { Remove-DnsServerResourceRecord -ZoneName $dnsZone -ComputerName $dnsServer -InputObject $_ -Force} 
            }

        }
        $errorVar = $null
        # On exécute la commande en local mais avec des credentials spécifiques
        Invoke-Command -ComputerName $this.psEndpointServer -ScriptBlock $scriptBlockContent -Authentication CredSSP -credential $this.credentials `
                        -ArgumentList @($this.dnsServer, $name, $zone) -ErrorVariable errorVar -ErrorAction:SilentlyContinue

        # Gestion des erreurs
        if($errorVar.count -gt 0)
        {
            Throw ("Error removing DNS information: {0}" -f ($errorVar -join "`n"))
        }    
        
    }
}