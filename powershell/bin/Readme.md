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