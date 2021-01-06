Les dossiers présents ici contiennent les types d'éléments suivants :
- Templates pour envoyer des mails
- Données ensuite utilisées pour faire des requêtes REST

## Description des fichiers présents à ce niveau


### epfl-deny-vra-sercices.json
Permet de spécifier quels services (au sens vRA) doivent être maqués à l'utilisateurs. 
Par défaut, tous les services se terminant par "(Public)" sont ajoutés dans l'entitlement de chaque BG.
Ce fichier, permet de faire en sorte de ne pas ajouter un service (ou un/des éléments de catalogue de celui-ci) à un Business Group du tenant EPFL dont l'unité se trouverait sous l'arborescence LDAP donnée.

### admin-bg.json
Pour effectuer des tests, les admins ont besoin de Business Groupes qui ne sont pas réellement en production mais qui doivent se comporter comme tel.
Ce fichier permet d'ajouter des informations pour des Business Groups dans les différents tenants.
Aucune approval policy ne sera mise en place pour ces Business Groups.

### itservices.json
Contient la liste des services IT pour lesquels il faut créer un Business Group dans le tenant ITSercices.

### mail-quotes.json
Juste pour le fun :rofl: pour ajouter des quotes aléatoires à la fin des mails envoyés aux admins.

### mandatory-entitled-items.json
Afin de pouvoir continuer à gérer les VM importées depuis MyVM sans pouvoir avoir la possibilité de demander une nouvelle VM de ce type, on doit ajouter des éléments du catalogue
non pas dans le service "VM (Public)" mais directement dans les "Entitled items" qui sont dans chaque "Entitlement". 
On liste donc ici ces éléments de catalogue à ajouter dans tous les cas, en définissant s'ils ont besoin d'avoir une approval policy ou pas.