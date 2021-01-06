## Descriptif des fichiers JSON
Les fichiers JSON présents ici sont utilisés pour la partie XaaS NAS.

### applicative-svm.json
**NOTE** Valable uniquement pour la partie applicative

Contient, par environnement (test/dev/prod) et par protocole (CIFS/NFSv3) la liste des SVM qui peuvent être utilisées pour services des volumes NAS applicatifs.

### faculty-mapping.json
**NOTE** Valable uniquement pour la partie Collaborative

Permet de gérer l'historique de changement de noms des facultés au niveau des noms qu'ont maintenant les SVM du NAS. Par exemple, par le passé, c'était "VPSI" et maintenant, c'est "SI"... et les SVM créées par le passé ont "VPSI" dans leur nom. Il faut donc faire un mapping quelque part (dans le fichier en question) pour dire que les SVM de l'actuelle faculté "SI" sont aussi celles qui contiennent "VPSI" (dans le cas où on déciderait de créer de nouvelles SVM "SI" en plus).

### faculty-svm.json
**NOTE** Valable uniquement pour la partie Collaborative

Par défaut, on peut déterminer les SVM d'une faculté grâce à leur nom (ils contiennent le nom de la faculté). Cependant, il se peut qu'il y ait d'autres SVM (SCXDATA, etc...) qui doivent aussi être "présentées" à l'utilisateur lors d'une demande de volume collaboratif pour une faculté donnée.
La liste des SVM à ajouter peut être définie par environnement
