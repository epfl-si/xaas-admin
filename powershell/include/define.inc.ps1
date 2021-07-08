<#
   BUT : Contient les constantes utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>

<#
Ici, on met un bout de code qui s'occupe simplement d'attendre entre 0 et une seconde avant d'exécuter la suite. Pourquoi ?
Simplement parce qu'il peut arriver dans de rares cas que 2 exécutions de scripts soient lancées par vRO pile au même moment..
Donc ça fait conflit sur l'accès aux fichiers logs. Il y a même eu un cas où les 2 exécutions avaient le même fichier log, même
si on avait fait en sorte de mettre le nombre de millisec du timestamp à la création du fichier!
#>
Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 1000)


# ---------------------------------------------------------
# Global
$global:RESOURCES_FOLDER            = ([IO.Path]::Combine("$PSScriptRoot", "..", "resources"))
$global:BINARY_FOLDER               = ([IO.Path]::Combine("$PSScriptRoot", "..", "bin"))
$global:CONFIG_FOLDER               = ([IO.Path]::Combine("$PSScriptRoot", "..", "config"))
$global:DATA_FOLDER                 = ([IO.Path]::Combine("$PSScriptRoot", "..", "data"))
$global:LOGS_FOLDER                 = ([IO.Path]::Combine("$PSScriptRoot", "..", "logs"))
$global:MAIL_TEMPLATE_FOLDER        = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "mail-templates"))
$global:JSON_TEMPLATE_FOLDER        = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "json-templates"))
$global:VRA_JSON_TEMPLATE_FOLDER    = ([IO.Path]::Combine($global:JSON_TEMPLATE_FOLDER, "vRAAPI"))
$global:JSON_2ND_DAY_ACTIONS_FOLDER = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "2nd-day-actions"))
$global:YAML_TEMPLATE_FOLDER        = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "yaml-templates"))
$global:ERROR_FOLDER                = ([IO.Path]::Combine("$PSScriptRoot", "..", "errors"))
$global:RESULTS_FOLDER              = ([IO.Path]::Combine("$PSScriptRoot", "..", "results"))


$global:ENV_FILE = ([IO.Path]::Combine("$PSScriptRoot", "..", "..", ".env"))


# Environnements
$global:TARGET_ENV__DEV  = 'dev'
$global:TARGET_ENV__TEST = 'test'
$global:TARGET_ENV__PROD = 'prod'

# Pour valider le nom d'environnement passé en paramètre au script principal
$global:TARGET_ENV_LIST = @($global:TARGET_ENV__DEV
					        $global:TARGET_ENV__TEST
					        $global:TARGET_ENV__PROD)

# Nom du tenant par défaut
$global:VRA_TENANT__DEFAULT      = "vsphere.local"
$global:VRA_TENANT__EPFL         = "EPFL"
$global:VRA_TENANT__ITSERVICES   = "ITServices"
$global:VRA_TENANT__RESEARCH     = "Research"

# Nom du groupe "groups" utilisé par les admins vRA. Sera utilisé principalement pour gérer les groupes dans "groups"
$global:VRA_GROUPS_ADMIN_GROUP = "vsissp-prod-admins"

# Nom des tenants que l'on devra traiter
$global:TARGET_TENANT_LIST = @($global:VRA_TENANT__EPFL, $global:VRA_TENANT__ITSERVICES, $global:VRA_TENANT__RESEARCH<#, $global:VRA_TENANT__DEFAULT #>)


# Information sur les services au sens vRA
#FIXME: A priori on devrait pouvoir supprimer ceci
$global:VRA_SERVICE_SUFFIX__PUBLIC  =" (Public)"

# Nom des custom properties à utiliser
$global:VRA_CUSTOM_PROP_EPFL_PROJECT_ID             = "ch.epfl.vra.project.id"
$global:VRA_CUSTOM_PROP_VRA_PROJECT_TYPE            = "ch.epfl.vra.project.type"
$global:VRA_CUSTOM_PROP_VRA_PROJECT_STATUS          = "ch.epfl.vra.project.status"
$global:VRA_CUSTOM_PROP_VRA_BG_RES_MANAGE           = "ch.epfl.vra.project.res.manage"
$global:VRA_CUSTOM_PROP_VRA_BG_ROLE_SUPPORT_MANAGE  = "ch.epfl.vra.project.roles.support.manage"
$global:VRA_CUSTOM_PROP_VRA_TENANT_NAME             = "ch.epfl.vra.tenant.name"
$global:VRA_CUSTOM_PROP_VRA_PROJECT_NAME            = "ch.epfl.vra.project.name"
$global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER = "ch.epfl.billing.financecenter"
$global:VRA_CUSTOM_PROP_EPFL_BILLING_ENTITY_NAME    = "ch.epfl.billing.entity.name"
$global:VRA_CUSTOM_PROP_EPFL_DEPLOYMENT_TAG         = "ch.epfl.deployment_tag"
$global:VRA_CUSTOM_PROP_EPFL_VM_NOTIFICATION_MAIL   = "ch.epfl.owner_mail"


# Statuts de Business Group possibles
# FIXME: Utiliser des types énumérés
$global:VRA_PROJECT_STATUS__ALIVE = "alive"
$global:VRA_BG_STATUS__GHOST = "ghost"

# Valeurs possibles pour la gestion des Réservations du Business Group
$global:VRA_BG_RES_MANAGE__AUTO  = "auto"
$global:VRA_BG_RES_MANAGE__MAN   = "man"
 
# Pour filtrer et ne prendre que les groupes AD modifiés durant les X derniers jours pour la création des éléments dans vRA
$global:AD_GROUP_MODIFIED_LAST_X_DAYS = 2

# Nombre de digits des préfixes de machine
$global:VRA_MACHINE_PREFIX_NB_DIGITS = 4

### ISO
# Nom chemin jusqu'aux volumes NAS où se trouvent les ISO privées
$global:NAS_PRIVATE_ISO_TEST = "\\nassvmmix01\si_vsissp_iso_priv_repo_t02_app"
$global:NAS_PRIVATE_ISO_PROD = "\\nassvmmix01\si_vsissp_iso_priv_repo_p01_app"

# Le nombre de jours pendant lesquels on garde les fichiers ISO privés avant de les supprimer
$global:PRIVATE_ISO_LIFETIME_DAYS = 30

# Type d'élément géré nativement par vRA
$global:VRA_ITEM_TYPE_VIRTUAL_MACHINE = "VMware Cloud Templates"

## Fonctionnement alternatif
# Fichiers utilisés pour "altérer" le fonctionnement des scripts
$global:SCRIPT_ACTION_FILE__RECREATE_APPROVAL_POLICIES   = "RECREATE_APPROVAL_POLICIES"
$global:SCRIPT_ACTION_FILE__SIMULATION_MODE              = "SIMULATION_MODE"
$global:SCRIPT_ACTION_FILE__TEST_MODE                    = "TEST_MODE"
$global:SCRIPT_ACTION_FILE__FORCE_ISO_FOLDER_ACL_UPDATE  = "FORCE_ISO_FOLDER_ACL_UPDATE"


## NSX
# Nom de la section avant laquelle il faut créer les sections de Firewall vide
$global:NSX_CREATE_FIREWALL_EMPTY_SECTION_BEFORE_NAME = "Legacy VLAN"

# Mail
$global:VRA_MAIL_SUBJECT_PREFIX = "vRA Service [{0}->{1}]"
$global:VRA_MAIL_SUBJECT_PREFIX_NO_TENANT = "vRA Service [{0}]"
$global:MAIL_QUOTES_FILE = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "mail-quotes.json"))

## Billing
$global:XAAS_BILLING_DATA_FOLDER = ([IO.Path]::Combine("$PSScriptRoot", "..", "data", "billing"))
$global:XAAS_BILLING_ROOT_DOCUMENT_TEMPLATE = ([IO.Path]::Combine("$PSScriptRoot", "..", "resources", "billing", "xaas-billing-pdf-document.html"))
$global:XAAS_BILLING_ITEM_DOCUMENT_TEMPLATE = ([IO.Path]::Combine("$PSScriptRoot", "..", "resources", "billing", "xaas-billing-pdf-item.html"))
$global:XAAS_BILLING_MAIL_TEMPLATE = ([IO.Path]::Combine("$PSScriptRoot", "..", "resources", "billing", "xaas-billing-mail.html"))
$global:XAAS_BILLING_PDF_FOLDER = ([IO.Path]::Combine("$PSScriptRoot", "..", "billing"))

# Type d'entité à facturer
enum BillingEntityType 
{
    Unit
    Service
    Project
    NotSupported # Pour les éléments non supportés
}

# Types d'entitlement possibles
enum EntitlementType
{
    User
    Admin
}

# Type de rôles
enum UserRole
{
    Admin
    User
    Support
}

# Rôles utilisateurs dispo dans vRA
enum vRAUserRole
{
    Administrator
    Members
    Viewers
}

# Type de source pour un élément de catalogue
enum ContentSourceType
{
    CatalogSourceIdentifier # Source = regroupement d'Items
    CatalogItemIdentifier   # Item
}


# Type de projet possible
enum ProjectType
{
    # Pour les 3 tenants
    Unit
    Service
    Project

    Admin
    # Type de catalogues
    PublicCatalog
    PrivateCatalog
}

# Type du catalogue
enum CatalogProjectPrivacy
{
    Private
    Public
}

# Type de contenu GitHub
enum GitHubContentType
{
    CloudTemplates
    ActionBasedScripts
    TerraformConfigurations
}

<# Type de policy que l'on peut avoir
Service Broker -> Content & Policies -> Policies -> Definitions

NOTE: Ces noms correspondent à la fin des noms utilisés par vRA pour identifier les types de policies:

com.vmware.policy.deployment.approval
com.vmware.policy.deployment.action
com.vmware.policy.deployment.lease
#>
enum PolicyType
{
    Approval 
    Action
    Lease
}

<#
Tout comme pour PolicyType, ces valeurs correspondent à ce qui est possible pour identifier un rôle:

ROLE:administrator
ROLE:infrastructure_administrator
ROLE:member
#>
enum PolicyRole
{
    Administrator
    Member
    Infrastructure_Administrator
}

# Utilisé comme paramètre de fonction pour définir quel type d'approval policy on veut
enum ApprovalPolicyType
{
    NewItem
    Day2Action
}

