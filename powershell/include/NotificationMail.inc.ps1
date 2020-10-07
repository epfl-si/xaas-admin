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

        # 4. Ajout de la quote de fin
        $this.getRandomHTMLQuote() | Out-File $tmpMailFile -Encoding default -Append

        $mailMessage = Get-Content $tmpMailFile -Encoding UTF8 | Out-String
        Remove-Item $tmpMailFile -Force

        Send-MailMessage -From ("noreply+{0}" -f $this.sendToAddress) -To $this.sendToAddress -Subject $mailSubject `
                        -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding Unicode
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie une citation au hasard parmi celles présentes dans la liste.
            Cette fonction est complètement inutile pour le bon fonctionnement du code 
            mais elle aura pour effet d'agrémenter les mails envoyé avec un petit truc rigolo

        RET : La citation en HTML
    #>
    hidden [string] getRandomHTMLQuote()
    {
        $quotes = @(
            @{
                quote = "One cries because one is sad... for example, I cry because others are stupid and that makes me sad"
                author = "Sheldon Cooper"
            },
            @{
                quote = "What are you doing for Christmas? Bazinga I don't care"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Love is in the air? Wrong, Nitrogen, Oxygen and Carbon Dioxide are in the air"
                author = "Sheldon Cooper"
            }
            ,
            @{
                quote = "I'm quite aware of the way humans usually reproduce, which is messy, unsanitary and involves loud and unnecessary appeals to a deity"
                author = "Sheldon Cooper"
            },
            @{
                quote = "I don't say anything. I merely offer you a facial expression that suggests you've gone insane"
                author = "Sheldon Cooper"
            },
            @{
                quote = "My mom smokes in the car. Jesus is ok with it, but we can't tell dad"
                author = "Sheldon Cooper"
            },
            @{
                quote = "I'm not insane. My mother had me tested"
                author = "Sheldon Cooper"
            },
            @{
                quote = "What computer do you have? And please don't say a white one"
                author = "Sheldon Cooper"
            },
            @{
                quote = "You don't think if I were wrong I'd know it ?"
                author = "Sheldon Cooper"
            },
            @{
                quote = "I'm listening, it just takes me a minute to process so much stupid all at once"
                author = "Sheldon Cooper"
            },
            @{
                quote = "A neutron walks into a bar and asks how much for a drink. The barman replies for you no charge"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Cats make wonderful companions. They don't argue or question my intellectual authority"
                author = "Sheldon Cooper"
            },
            @{
                quote = "People say you can't live without love... I think Oxygen is more important"
                author = "Sheldon Cooper"
            },
            @{
                quote = "I have never said that you are not good at what you do. It's just that what you do is not worth doing it"
                author = "Sheldon Cooper"
            },
            @{
                quote = "You're just in time. I believe I have isolated the algorithm for making friends"
                author = "Sheldon Cooper"
            },
            @{
                quote = "I am immune to your saracsm"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Change is never fine they say it but... it's not"
                author = "Sheldon Cooper"
            },
            @{
                quote = "There's a thin line between 'wrong' and 'visionary'. Unfortunately, you have to be visionary to see it"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Bazinga, I don't care"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Knock knock knock Penny! knock knock knock Penny! knock knock knock Penny!"
                author = "Sheldon Cooper"
            },
            @{
                quote = "They were threatend by my intelligence and too stupid to know that's why they hated me"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Interesting. Sex works even better than chocolate to modify behavior. I wonder if anyone else has stumbled onto this"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Coffee's out of the question. When I moved to California, I promised my mother that I wouldn't start doing drugs"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Under normal circumstances I'd say I told you so. But, as I have told so with such vehemence and frequency already the phrase has lost all meaning. Therefore, I will be replacing it with the phrase, I have informed you thusly"
                author = "Sheldon Cooper"
            },
            @{
                quote = "For the record, I do have genitals. They're functional and aesthetically pleasing"
                author = "Sheldon Cooper"
            },
            @{
                quote = 'What exactly does that expression mean, "friends with benefits" ? Does he provide her with health insurance?'
                author = "Sheldon Cooper"
            },
            @{
                quote = "You can't make a half sandwich. If it's not half of a whole sandwich, it's just a small sandwich"
                author = "Sheldon Cooper"
            },
            @{
                quote = "I think that you (Leonard) have as much of a chance of having sexual relationship with Penny as the Hubble telescope does of discovering at the center of every black hole is a little man with a flashlight searching for a circuit breaker"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Interesting. You're afraid of insects and women. Ladybugs must render you catatonic"
                author = "Sheldon Cooper"
            },
            @{
                quote = "That's my spot!"
                author = "Sheldon Cooper"
            },
            @{
                quote = "Always code as if the person who will maintain your code is a maniac serial killer that knows where you live"
                author = "Unknown"
            },
            @{
                quote = "Well, I suppose now is the time for me to say something profound... ...nothing comes to mind"
                author = "Jack O'Neill"
            },
            @{
                quote = "Well, you do have a penchant for pulling brilliant ideas out of your butt"
                author = "Jack O'Neill"
            },
            @{
                quote = "How many times have I told you? Don't get caught by bad guys"
                author = "Jack O'Neill"
            },
            @{
                quote = "Well, I suppose now is the time for me to say something profound... ...nothing comes to mind"
                author = "Jack O'Neill"
            },
            @{
                quote = "I'm too small for Twiter. And roller coasters. And sitting with my feet on the floor. Hope you enjoyed the prenatal cigarettes, Mom"
                author = "Bernadette Wolowitz"
            },
            @{
                quote = "Oh boo-hoo, you're not going to space!"
                author = "Bernadette Wolowitz"
            },
            @{
                quote = "I'm a very vengeful person... With access to weaponized smallpox"
                author = "Bernadette Wolowitz"
            },
            @{
                quote = "They don't call me Brown Dynamite for nothing"
                author = "Rajesh Koothrappali"
            },
            @{
                quote = "Phone drop!! But I won't because I dont have Apple Care"
                author = "Rajesh Koothrappali"
            },
            @{
                quote = "Whassup Moonpie?"
                author = "Penny Hofstadter"
            },
            @{
                quote = "I'm a vegetarian, except for fish, and the occasional steak. I LOVE STEAK"
                author = "Penny Hofstadter"
            },
            @{
                quote = "I need to go back to dating dumb guys from the gym"
                author = "Penny Hofstadter"
            },
            @{
                quote = "I have got to learn how to spell 'Hofstadter'. I know the's a 'D' in there, but it keeps moving every time I try and write it"
                author = "Penny Hofstadter"
            },
            @{
                quote = "You don't have to thank me everytime we have sex sweetie"
                author = "Penny Hofstadter"
            },
            @{
                quote = "What's up, Shel-Bot?"
                author = "Penny Hofstadter"
            },
            @{
                quote = "Sheldon, that's not what girlfriends are for. Although you don't use them for what they're for, so what do I know?"
                author = "Penny Hofstadter"
            },
            @{
                quote = "How I am with pets? Well, I did take care of Sheldon for 15 years and he only bite me twice"
                author = "Leonard Hofstadter"
            },
            @{
                quote = "(to Sheldon) sometimes your movements are so life like I forget you are not a real boy"
                author = "Leonard Hofstadter"
            },
            @{
                quote = "What ya doin' there? Working on a new plan to catch the road runner?"
                author = "Leonard Hofstadter"
            },
            @{
                quote = "12 years after high school and I'm still at the nerd table"
                author = "Leonard Hofstadter"
            },
            @{
                quote = "Would someone please turn off the Sheldon commentary track?"
                author = "Leonard Hofstadter"
            },
            @{
                quote = "The guy is one lab accident away from being a super villain"
                author = "Leonard Hofstadter"
            },
            @{
                quote = "I am a horny engineer, I never joke about math or sex"
                author = "Howard Wolowitz"
            },
            @{
                quote = "You got her to have sex with you. Obviously your super power is brainwashing"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Love is not a sprint, it's a marathon a relentless pursuit that only ends when she falls into your arms - or hits you with the pepper spray"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Hey girl, are you made of copper and tellurium? Because your are CuTe"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Is your name WiFi? Because I'm feeling a connection"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Hey girl, do you love water? That means you alread love 80% of me"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Are you Google? Because you have everthing I'm searching for"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Look what you created here, it's lik Nerdvada"
                author = "Howard Wolowitz"
            },
            @{
                quote = "If it's 'creepy' to use the internet, military satellites, and robot aircraft to find a house full of gorgeous young models so I can drop in on them unexpected, then fine, I'm 'creepy'"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Ray, there's no place for truth on the internet"
                author = "Howard Wolowitz"
            },
            @{
                quote = "The way I see it, I'm halfway to pity sex"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Whaddup science b*tches?"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Baby you turn my floppy disk into a hard drive"
                author = "Howard Wolowitz"
            },
            @{
                quote = "Are you saying you want to spank me?"
                author = "Amy Farrah Fowler"
            },
            @{
                quote = "I'm just saying, second base is here"
                author = "Amy Farrah Fowler"
            },
            @{
                quote = 'The only person who signed my yearbook was my mother. "Dear Amy, self respect and a hymen are far better than friends and fun. Love, Mom'
                author = "Amy Farrah Fowler"
            },
            @{
                quote = "Howard's mother had a heart attack because I have sex with him and she can't"
                author = "Bernadette Wolowitz"
            },
            @{
                quote = "<u>Howard:</u> Boy if these walls could talk.<br><u>Leonard:</u> They'd say: 'Why does he touch himself so much?' "
                author = "Big Bang Theory"
            },
            @{
                quote = "<u>Leonard:</u> I'm gonna have sex with you right here, right now, on that washing machine.<br><u>Penny:</u> No you're not.<br><u>Leonard:</u> Come on, please"
                author = "Big Bang Theory"
            },
            @{
                quote = "<u>Sheldon:</u> Excuse me! You're not supposed to be enjoying this.<br><u>Amy:</u> Then maybe you should spank me harder"
                author = "Big Bang Theory"
            }

        )

        $quoteNo = (Get-Random -Maximum ($quotes.count-1))
        return ("<i>{0}.</i> <small>({1})</small>" -f $quotes[$quoteNo].quote, $quotes[$quoteNo].author)
    }    
    
}