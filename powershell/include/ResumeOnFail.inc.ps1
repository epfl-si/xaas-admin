<#
   BUT : Contient une classe avec les fonctions nécessaires pour sauvegarder une progression 
        d'exécution d'un script et faire en sorte de pouvoir la reprendre là où elle était.
        
   AUTEUR : Lucien Chaboudez
   DATE   : Février 2020

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class ResumeOnFail
{
    hidden [String]$progressFile


    <#
	-------------------------------------------------------------------------------------
		BUT : Constructeur de classe
	#>
    ResumeOnFail()
    {
        # Création du chemin d'accès au fichier de suivi de la progression
        $this.progressFile =  "{0}.progress" -f (((Get-PSCallStack)[1]).ScriptName)
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Sauvegarde la progression
		
		IN  : $progress -> objet qui représente la progression
	#>
    [void] save([object]$progress)
    {
       $progress | ConvertTo-Json | Out-File $this.progressFile
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Charge une progression depuis un fichier.
        
        RET : objet avec la progression
                $null si le fichier n'existe pas.
	#>
    [object] load()
    {
        if(Test-Path $this.progressFile)
        {
            return Get-Content -path $this.progressFile | ConvertFrom-Json
        }
        return $null
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Efface le fichier qui enregistre la progression
	#>
    [void] clean()
    {
       if(Test-Path $this.progressFile)
       {
           Remove-Item -Path $this.progressFile
       }
    }
}