Les dossiers présents ici contiennent les types d'éléments suivants :
- Templates pour envoyer des mails
- Données ensuite utilisées pour faire des requêtes REST

## Description des fichiers présents à ce niveau


### epfl-deny-vra-sercices.json
Permet de spécifier quels services (au sens vRA) doivent être maqués à l'utilisateurs. 
Par défaut, tous les services se terminant par "(Public)" sont ajoutés dans l'entitlement de chaque BG.
Ce fichier, permet de faire en sorte de ne pas ajouter un service (ou un/des éléments de catalogue de celui-ci) à un Business Group du tenant EPFL dont l'unité se trouverait sous l'arborescence LDAP donnée.

### epfl-manual-units.json
Pour effectuer des tests, les admins ont besoin de Business Groupes qui ne sont pas réellement en production mais qui doivent se comporter comme tel.
Ce fichier permet d'ajouter des informations pour des Business Groups dans le tenant EPFL qui seraient utilisés à des fin de tests.
Les approval policies qui seront mises en place pour ces Business Groups seront les mêmes que pour les autres, peu importe l'environnement (test ou prod).

### itservices.json
Contient la liste des services IT pour lesquels il faut créer un Business Group dans le tenant ITSercices.

### mail-quotes.json
Juste pour le fun :rofl: pour ajouter des quotes aléatoires à la fin des mails envoyés aux admins.