 # Provenance des fichiers

## Curl

Les binaires de Curl peuvent être téléchargée ici: https://curl.haxx.se/download.html#Win64

---

 ## iText

Les DLL `itextsharp.dll` et `itextsharp.xmlworker.dll` peuvent être récupérées à 2 endroits différents:

* https://www.nuget.org/packages/itextsharp.xmlworker/
* https://www.nuget.org/packages/iTextSharp/

La procédure pour les récupérer et les mettre à jour est la suivante:

1. Aller à l'URL donnée ci-dessus
1. Sur la droite, cliquer sur "**Download Package**"
1. Le fichier téléchargé est un `*.nupkg`, il est possible d'extraire son contenu avec [7-ZIP](https://www.7-zip.org/)
1. Extraire le contenu avec [7-ZIP](https://www.7-zip.org/)
1. Aller dans le dossier `lib` et copier la DLL qui s'y trouve dans le dossier courant.

**Attention**

Les deux DLL doivent avoir le même numéro de version sinon cela ne va pas fonctionner correctement.


---

## FileACL

Difficile de dire où le trouver car le développement a été arrêté depuis longtemps, donc il faut bien le garder au chaud ce binaire!

---

## PSCP

Ceci est l'utilitaire de Putty pour faire des SCP. Attention à bien conserver la version présente sur le repository et éviter de prendre la toute dernière version sur le site officiel. Pourquoi? simplement parce que la dernière version ne fonctionne pas pour notre environnement... aucune idée de la raison exacte

---

## TKGI

Utilitaire pour K8s (Kubernetes). Permet de créer et gérer les clusters.