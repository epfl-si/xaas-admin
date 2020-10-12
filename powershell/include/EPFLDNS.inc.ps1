<#
   	BUT : Contient une classe permetant de faire des requêtes dans le DNS

   	AUTEUR : Lucien Chaboudez
   	DATE   : Octobre 2020
	
#>
class EPFLDNS
{
    [System.Management.Automation.PSCredential]$credentials
    [string] $server


    <#
	-------------------------------------------------------------------------------------
		BUT : Constructeur de classe

		IN  : $server       -> Nom du serveur DNS
		IN  : $username     -> Nom d'utilisateur pour faire la connexion
        IN  : $password     -> Mot de passe
        
        RET : Instance de la classe
	#>
    EPFLDNS([string]$server, [string]$username, [string]$password)
    {
        $this.credentials = New-Object System.Management.Automation.PSCredential -ArgumentList @($username, `
                                            (ConvertTo-SecureString -String $password -AsPlainText -Force))
        
        $this.server = $server
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

        # On exécute la commande en local mais avec des credentials spécifiques
        Invoke-Command -ComputerName $env:COMPUTERNAME -ScriptBlock $scriptBlockContent -Authentication CredSSP -credential $this.credentials `
                        -ArgumentList $this.server, $name, $ip, $zone 
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Supprime un enregistrement dans le DNS

		IN  : $name         -> Nom IP
		IN  : $ip           -> Adresse IP
        IN  : $zone         -> Nom de la Zone DNS
	#>
    [void] unregisterDNSIP([string]$name, [string]$ip, [string]$zone)
    {

        $scriptBlockContent =
        {
            # Récupération des paramètres
            $server, $dnsName, $zoneName = $args
            
            $nodeARecord = Get-DnsServerResourceRecord -ZoneName $zoneName -ComputerName $server -Node $dnsName -RRType A -ErrorAction SilentlyContinue
            
            if($null -ne $nodeARecord)
            {
                Remove-DnsServerResourceRecord -ZoneName $zoneName -ComputerName $server -InputObject $nodeARecord -Force
            }

        }

        # On exécute la commande en local mais avec des credentials spécifiques
        Invoke-Command -ComputerName $env:COMPUTERNAME -ScriptBlock $scriptBlockContent -Authentication CredSSP -credential $this.credentials `
                        -ArgumentList $this.server, $name, $zone

    }
}