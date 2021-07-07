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
        
        IN  : $execIdentifier       -> pour identifier l'exécution en cours car le même
                                        script peut être exécuté au même moment mais avec des
                                        paramètres différents
	#>
    ResumeOnFail([string]$identifier)
    {
        # Création du chemin d'accès au fichier de suivi de la progression
        $this.progressFile =  ("{0}.{1}.progress" -f (((Get-PSCallStack)[1]).ScriptName), $identifier.ToLower())
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Sauvegarde la progression
		
		IN  : $progress -> objet qui représente la progression
	#>
    [void] save([object]$progress)
    {
        # On ne fait pas de "pipe" pour transformer $progress en JSON car si c'est un tableau avec un seul élément, on aura juste l'élément et on 
        # perdra la notion de tableau... c'est un bug à la con de PowerShell... il faut le passer en paramètre à "ConvertTo-Json" pour que
        # l'on ait bien un tableau comme résultat
       (ConvertTo-Json $progress) | Out-File $this.progressFile
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Charge une progression depuis un fichier.
        é
        RET : objet avec la progression
                $null si le fichier n'existe pas.
	#>
    [object] load()
    {
        $result = $null
        if(Test-Path $this.progressFile)
        {
            $content = Get-Content -path $this.progressFile 
    
            if(($null -ne $content) -and ($content.Trim() -ne ""))
            {
                $result = $content | ConvertFrom-Json
            }
        }
        return $result
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