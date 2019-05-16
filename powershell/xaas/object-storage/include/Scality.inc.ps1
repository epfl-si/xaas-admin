<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Scality
         de manière simple

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019    
#>
class Scality
{
	hidden [string]$s3EndpointUrl


	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $endpointUrl          -> URL du endpoint Scality
	#>
	Scality([string]$endpointUrl)
	{
        $this.s3EndpointUrl = $endpointUrl
    }
    

    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie un utilisateur de Scality
        
        IN  : $username     -> Nom de l'utilisateur
	#>
    [PSObject] getUser([string]$username)
    {
        return Get-IAMUserList -EndpointUrl $this.s3EndpointUrl | Where-Object {$_.Username -eq $username}
    }


}