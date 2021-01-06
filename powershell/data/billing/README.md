## Descriptif des fichiers JSON

### bill-to-mail.json
Valable uniquement pour le tenant **EPFL**
Contient les informations permettant de faire en sorte que ce qui se trouve sous une arborescence LDAP donnée soit facturé via un envoi par mail au lieu d'être ajouté dans Copernic.
On peut définir 2 choses différentes:

- Adresse mail fixe à utiliser pour les unités se trouvant sous l'arborescence LDAP
- Fonction à appeler pour renvoyer l'adresse mail à utiliser. Les informations de l'unité courante seront envoyées à la fonction pour qu'elle puisse utiliser celles-ci.

### ge-unit-mapping.json
Pour effectuer la facturation, on a besoin d'avoir un centre financier pour chaque unité. Comme on prend aussi des unités de niveau 3, celles-ci n'ont pas de centre financier. Du coup, on essaie de chercher manuellement une unité de Gestion de niveau 4 mais ce n'est pas toujours facile car il n'y a aucune convention de nommage pour les unités de gestion par rapport aux unités "parentes". 
Pour gérer ce qu'on peut appeler des cas particuliers, le fichier `ge-unit-mapping.json` a été créé et il permet de manuellement spécifier quelle unité de Gestion (niveau 4) existe pour une unité de niveau 3

### services-sample.json
Fichier d'exemple pour la création d'un fichier `services.json` qui sera mis dans chacun des dossiers d'un type d'élément (Volume NAS, Bucket S3) à facturer.