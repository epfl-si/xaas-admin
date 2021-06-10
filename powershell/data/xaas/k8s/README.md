## Descriptif des fichiers JSON
Les fichiers JSON présents ici sont utilisés pour la partie XaaS K8s.

### resource-quota-limits.json
Permet de stocker quelques "limites" pour que les utilisateurs ne demandent pas "trop".
Par exemple, comme il n'est pas possible de récupérer dynamiquement le nombre de Workers min et max pour un plan donné, on stocke ces informations ici.
Et on y retrouve aussi le nombre maximum de LoadBalancers (et donc NodePorts, vu que liés) qui sont autorisés pour chaque namespace.