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
        # Pour essayer de faire l'action plusieurs fois si elle a planté
        $maxTries = 3
        $tryNo = 1

        $scriptBlockContent =
        {
            # Récupération des paramètres
            $dnsServer, $dnsName, $dnsIP, $dnsZone = $args
            
            Add-DnsServerResourceRecordA -Computername $dnsServer -Name $dnsName -ZoneName $dnsZone -CreatePtr -IPv4Address $dnsIP

        }

        # On tente de faire l'action plusieurs fois de suite en cas de problème
        While($tryNo -le $maxTries)
        {
            $errorVar = $null
            # On exécute la commande en local mais avec des credentials spécifiques
            Invoke-Command -ComputerName $this.psEndpointServer -ScriptBlock $scriptBlockContent -Authentication CredSSP -credential $this.credentials `
                            -ArgumentList @($this.dnsServer, $name, $ip, $zone)  -ErrorVariable errorVar -ErrorAction:SilentlyContinue

            # Si pas d'erreur 
            if($errorVar.count -eq 0)
            {
                # On peut sortir de la boucle car on a fait le job
                break
            }
            # Il y a eu une erreur
            else
            {
                # Si on a fait tous les essais auxquels on avait droit
                if($tryNo -eq $maxTries)
                {
                    # Propagation de l'erreur, on ne supprime pas ce qu'on a ajouté (potentiellement à moitié si PTR pas créé) car ça sera nettoyé par le script appelant
                    Throw ("Error adding DNS information: {0}" -f ($errorVar -join "`n"))
                }
                else # On a encore droit à un essai
                {
                    # On attend un petit peu 
                    Start-Sleep -Seconds 5

                    # On supprime l'entrée DNS
                    $this.unregisterDNSName($name, $zone)

                    # On attend un peu et on recommence
                    Start-Sleep -Seconds 5
                }
                
            }# Fin s'il y a eu une erreur

            $tryNo++

        }# FIN BOUCLE avec les essais
        
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