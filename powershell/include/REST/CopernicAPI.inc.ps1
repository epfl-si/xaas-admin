<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Copernic
         de manière simple.
         
   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2020

   VERSION : 1.0.0
#>
class CopernicAPI: RESTAPICurl
{
    hidden [string] $server
    hidden [string] $username
    hidden [string] $password


    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $server           -> Nom IP du serveur, avec le début de l'URL à utiliser car
                                   c'est différent entre prod (/pop/) et test (/poq/)
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
        
		RET : Instance de l'objet
	#>
    CopernicAPI([string]$server, [string]$username, [string]$password): base($server)
    {
        $this.server = $server
        $this.username = $username
        $this.password = $password

        $this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/json')

        # Mise à jour des headers
        $this.headers.Add('Authorization', ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))))
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une facture dans Copernic

        IN  : $serviceInfos         -> Objet avec les informations sur le service qui fait la facturation
                                        Le contenu de cet objet vient d'un fichier JSON qui se trouve dans
                                        le dossier "data/billing/<service>/service.json"
        IN  : $targetEnv            -> Environnement sur lequel on tourne pour savoir quel numéro d'article récupérer
        IN  : $billRef              -> Référence de la facture    
        IN  : $billDesc             -> Description de la facture
        IN  : $billPDFFiles         -> Tableau d'objets avec la liste des fichiers PDF à ajouter à la facture. Chaque élément du 
                                        tableau est un objet avec :
                                        .file -> chemin jusqu'au fichier PDF
                                        .desc -> description à mettre pour le fichier
        IN  : $entityInfos          -> Objet avec les informations sur l'entité à facturer, vient de la
                                        base de données
        IN  : $itemList             -> Tableau avec la liste des éléments à facturer, vient de la base de 
                                        données.
        IN  : $execMode             -> Mode d'exécution. Défini par environnement dans le fichier "config/config-billing.json"
        
        RET : Objet avec 2 entrées:
                .error  -> message d'erreur éventuel (si tout OK, il y a $null ici)
                .docNumber -> le numéro de l'élément ajouté dans Copernic
	#>
    [PSObject] addBill([PSObject]$serviceInfos, [string]$targetEnv, [string]$billRef, [string]$billDesc, [Array]$billPDFFiles, [PSObject]$entityInfos, [Array]$itemList, [string]$execMode)
    {
        # On commence par créer le nécessaire pour les items
        $formattedItemList = @()

        ForEach($item in $itemList)
        {
            # Suppression des éventuels retours à la ligne
            $itemDesc = $item.itemDesc -replace "\\n", " - "

            <# On ajoute l'unité à la description car passe celle-ci à Copernic en tant que "vraie" unité implique d'avoir déclaré 
            celle-ci au préalable dans Copernic et si elle n'existe pas, l'erreur est mal gérée. Quentin Estoppey conseille de 
            plutôt mettre l'unité dans la description de l'élément, ce qu'on fait donc ici #>
            $itemDesc = "{0} [{1}]" -f $itemDesc, $item.itemUnit

            $replace = @{
                # numéro d'article en fonction de l'environnement
                prestationCode = $serviceInfos.prestationCode.$targetEnv
                itemQuantity = $item.itemQuantity
                unitPricePerMonthCHF = $serviceInfos.unitPricePerMonthCHF.($entityInfos.entityType)
                itemNameAndDesc = $itemDesc
            }

            $formattedItemList += $this.createObjectFromJSON("xaas-bill-item.json", $replace)
        }


        #################################
        # Création des informations pour les attachments de la facture
        $attachments = @()

        # Parcours des fichiers à ajouter
        ForEach($PDFFile in $billPDFFiles)
        {
            # On commence par la facture en elle-même
            $replace = @{
                pdfBillFileName = (Split-Path $PDFFile.file -leaf)
                pdfBillFileDescription = $PDFFile.desc
                pdfBillFileBase64 = ([Convert]::ToBase64String([IO.File]::ReadAllBytes($PDFFile.file)))
            }

            $attachments += $this.createObjectFromJSON("xaas-bill-pdf-attachment.json", $replace)
        }


        #################################
        # Création ensuite des informations pour la facture
        
        $replace = @{
            # header
            orderNumber = $billRef
            financeCenterNo = $entityInfos.entityFinanceCenter
            description = $billDesc
            # shipper
            shipperName = $serviceInfos.copernic.shipperName
            shipperSciper = $serviceInfos.copernic.shipperSciper
            shipperFund = $serviceInfos.copernic.shipperFund
            shipperMail = $serviceInfos.copernic.shipperMail
            shipperPhone = $serviceInfos.copernic.shipperPhone
            # shipper_imputation
            shipperImputationNoBilledSVC = $serviceInfos.copernic.shipperImputationNoBilledSVC

            # Type d'exécution
            execMode = $execMode
        }

        $body = $this.createObjectFromJSON("xaas-bill.json", $replace)

        # Ajout des items
        $body.items = $formattedItemList
        # Ajout des PDF attachés
        $body.attachment = $attachments

        # Pour le debug
        #$body | ConvertTo-JSON -Depth 20 | Out-file "D:\IDEVING\IaaS\git\xaas-admin\powershell\billing\JSON.json"

        $uri = "https://{0}/RESTAdapter/api/sd/facture" -f $this.server

        # Exécution de la requête et transformation en objet
        $callRes = $this.callAPI($uri, "Post", $body) 

        # Structure pour le renvoi du résultat
        $result = @{
            error = $null
            docNumber = $null
        }

        # Si erreur
        if($callRes.E_RESULT.item.IS_ERROR -ne "")
        {
            # Récupération du message d'erreur
            $result.error = $callRes.E_RESULT.item.LOG.item.MESSAGE
        }
        else # Pas d'erreur
        {
            # Récupéation de l'id du document ajouté
            $result.docNumber = $callRes.E_RESULT.item.DOC_NUMBER
        }

        return $result
    }


}