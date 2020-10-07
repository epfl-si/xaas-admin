<#
    BUT : Contient une classe permetant d'envoyer des mails de notification avec un header et footer
            défini (via des templates).
            Le sujet du mail va aussi être complété avec les informations du Tenant et de l'environnement.

            Pour chaque mail que l'on désire envoyer, il faudra donner le nom du template à utiliser (voir
            plus bas) ainsi qu'un tableau associatif avec la liste des éléments à remplacer dans le template
            ainsi que dans le sujet du mail.
            
            Certains de ces éléments n'ont pas besoin d'être donnés explicitement car il seront repris depuis
            les informations données à l'instanciation de la classe. Il s'agit de :
            - nom de l'environnement    -> utiliser {{targetEnv}} pour le référencer
            - nom du tenant             -> utiliser {{targetTenant}} pour le référencer


   	AUTEUR : Lucien Chaboudez
   	DATE   : Janvier 2020

	Documentation:
		

   	----------
   	HISTORIQUE DES VERSIONS
   	10.01.2020 - 1.0 - Version de base
#>
class NotificationMail
{
    hidden [string]$sendToAddress
    hidden [string]$templateFolder
    hidden [string]$mailSubjectPrefix
    hidden [System.Collections.IDictionary]$defaultValToReplace

    <#
    -------------------------------------------------------------------------------------
        BUT : Constructeur de classe

        IN  : $sendToAddress        -> Adresse mail à laquelle envoyer les mails
        IN  : $templateFolder       -> Chemin jusqu'au dossier où se trouvent les templates
                                        pour l'envoi de mail.
                                        NOTE: Celui-ci devra aussi contenir un fichier "_header.html"
                                        ainsi qu'un "_footer.html"
        IN  : $mailSubjectPrefix    -> Préfix à utiliser pour le sujet des mails envoyés par la classe
        IN  : $defaultValToReplace  -> Tableau associatif avec les valeurs à utiliser/remplacer dans 
                                        tous les mails qui pourront être envoyés par la classe.
                                        Ex: targetEnv et targetTenant
    #>
    NotificationMail([string]$sendToAddress, [string]$templateFolder, [string]$mailSubjectPrefix, [System.Collections.IDictionary]$defaultValToReplace)
    {
        $this.sendToAddress = $sendToAddress
        $this.templateFolder = $templateFolder
        $this.mailSubjectPrefix = $mailSubjectPrefix
        $this.defaultValToReplace = $defaultValToReplace
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le chemin jusqu'à un fichier Template donné par son nom "simple"

        IN  : $templateName     -> Nom du template dont on veut le chemin jusqu'au fichier.
    #>
    hidden [string] getPathToTemplateFile([string]$templateName)
    {
        return (Join-Path $this.templateFolder ("{0}.html" -f $templateName))
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Contrôle l'existence d'un fichier "template" et lève une exception si pas trouvé

        IN  : $templateName     -> Nom du template à contrôler. On va chercher celui-ci dans le dossier qui 
                                    à été donné lors de l'instanciation de la classe et on cherchera un 
                                    fichier appelé <templateName>.html
    #>
    hidden [void] checkTemplateFile([string]$templateName)
    {
        $templateFile = $this.getPathToTemplateFile($templateName)
        if(! (Test-Path $templateFile))
        {
            Throw ("Error sending notification mail. Template file not found ({0})" -f $templateFile)
        }
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Envoie un mail à l'adresse définie lors de l'instanciation de la classe
            Afin de pouvoir envoyer un mail en UTF8 depuis un script PowerShell encodé en UTF8, il 
            faut procéder d'une manière bizarre... il faut sauvegarder le contenu du mail à envoyer
            dans un fichier, avec l'encoding "default" (ce qui fera un encoding UTF8, je cherche pas
            pourquoi...) et ensuite relire le fichier en spécifiant le format UTF8 cette fois-ci...
            Et là, abracadabra, plus de problème d'encodage lorsque l'on envoie le mail \o/
        
        IN  : $mailSubject      -> Le sujet du mail. Le sujet pourra contenir des "{{elementName}}"
                                    qui seront remplacés par une autre valeur définie par le tableau $valToReplace.
        IN  : $templateName     -> Nom du template à utiliser. On va chercher celui-ci dans le dossier qui 
                                    à été donné lors de l'instanciation de la classe et on cherchera un 
                                    fichier appelé <templateName>.html
                                    Ce fichier pourra contenir du code HTML ainsi que des éléments {{elementName}}
                                    qui seront remplacés par une autre valeur définie par le tableau $valToReplace.

        IN  : $valToReplace     -> (Optionnel) tableau associatif avec les éléments à remplacer dans le template
    #>
    [void] send([string] $mailSubject, [string]$templateName)
    {
        $this.send($mailSubject, $templateName, @{})
    }
    [void] send([string] $mailSubject, [string]$templateName,  [System.Collections.IDictionary]$valToReplace)
    {
        # On commence par contrôler l'existence des fichiers
        $this.checkTemplateFile("_header")
        $this.checkTemplateFile("_footer")
        $this.checkTemplateFile($templateName)

        # Mise à jour du sujet du mail
        $mailSubject = "{0}: {1}" -f $this.mailSubjectPrefix, $mailSubject

        # Fichier temporaire pour la création du mail
        $tmpMailFile = (New-TemporaryFile).FullName

        # 1. Ajout du header
        Get-Content -Path $this.getPathToTemplateFile("_header") | Out-File $tmpMailFile -Encoding default


        # 2. Contenu du mail
        $mailMessage = Get-Content -Path $this.getPathToTemplateFile($templateName)

        # Ajout des infos sur le tenant et environnement
        $valToReplace += $this.defaultValToReplace

        # Parcours des remplacements à faire
        foreach($search in $valToReplace.Keys)
        {
            $replaceWith = $valToReplace.Item($search)

            $search = "{{$($search)}}"

            # Mise à jour dans le mail
            $mailMessage =  $mailMessage -replace $search, $replaceWith
            $mailSubject =  $mailSubject -replace $search, $replaceWith
        }
        
        $mailMessage | Out-File $tmpMailFile -Encoding default -Append


        # 3. Ajout du footer
        Get-Content -Path $this.getPathToTemplateFile("_footer") | Out-File $tmpMailFile -Encoding default -Append


        $mailMessage = Get-Content $tmpMailFile -Encoding UTF8 | Out-String
        Remove-Item $tmpMailFile -Force

        Send-MailMessage -From ("noreply+{0}" -f $this.sendToAddress) -To $this.sendToAddress -Subject $mailSubject `
                        -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding Unicode
    }

    
}