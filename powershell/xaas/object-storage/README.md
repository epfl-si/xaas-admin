# Installation des tools PowerShell

La documentation officielle est ici: 
https://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up-windows.html


1. Ouvrir une console PowerShell en mode "Run as Administrator"

1. Lancer la commande d'installation des **AWS Tools**
    ```
    Install-Module -Name AWSPowerShell -Scope AllUsers
    ```

1. Lancer la commande d'installation des **AWS NetCore**
    ```
    Install-Module -Name AWSPowerShell.NetCore -AllowClobber -Scope AllUsers
    ```

1. Pour utiliser les modules dans un script, il faudra commencer par exécuter les commandes suivantes :
    ```
    Import-Module AWSPowerShell
    Import-Module AWSPowerShell.NetCore
    ```
