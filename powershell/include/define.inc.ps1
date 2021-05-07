<#
   BUT : Contient les constantes utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>


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

# Les types d'approval policies
$global:APPROVE_POLICY_TYPE__ITEM_REQ     = 'new'
$global:APPROVE_POLICY_TYPE__ACTION_REQ   = 'reconfigure'

# Information sur les services au sens vRA
$global:VRA_SERVICE_SUFFIX__PUBLIC  =" (Public)"
$global:VRA_SERVICE_SUFFIX__PRIVATE =" (Private)"

# Nom des custom properties à utiliser
$global:VRA_CUSTOM_PROP_EPFL_BG_ID                  = "ch.epfl.vra.bg.id"
$global:VRA_CUSTOM_PROP_VRA_BG_TYPE                 = "ch.epfl.vra.bg.type"
$global:VRA_CUSTOM_PROP_VRA_BG_STATUS               = "ch.epfl.vra.bg.status"
$global:VRA_CUSTOM_PROP_VRA_BG_RES_MANAGE           = "ch.epfl.vra.bg.res.manage"
$global:VRA_CUSTOM_PROP_VRA_BG_ROLE_SUPPORT_MANAGE  = "ch.epfl.vra.bg.roles.support.manage"
$global:VRA_CUSTOM_PROP_VRA_TENANT_NAME             = "ch.epfl.vra.tenant.name"
$global:VRA_CUSTOM_PROP_VRA_BG_NAME                 = "ch.epfl.vra.bg.name"
$global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER = "ch.epfl.billing.financecenter"
$global:VRA_CUSTOM_PROP_EPFL_BILLING_ENTITY_NAME    = "ch.epfl.billing.entity.name"
$global:VRA_CUSTOM_PROP_EPFL_DEPLOYMENT_TAG         = "ch.epfl.deployment_tag"


# Types de Business Group possibles
$global:VRA_BG_TYPE__ADMIN 	= "admin"
$global:VRA_BG_TYPE__SERVICE  = "service"
$global:VRA_BG_TYPE__UNIT 	   = "unit"
$global:VRA_BG_TYPE__PROJECT  = "project"

# Statuts de Business Group possibles
$global:VRA_BG_STATUS__ALIVE = "alive"
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
$global:VRA_ITEM_TYPE_VIRTUAL_MACHINE = "Virtual Machine"

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
