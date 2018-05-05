PROBLEME:
tests: pour une raison que j'ignore, je ne parviens pas à exécuter la commande :
python src/manage.py test
qui crash
mais par contre
python src/manage.py test quotas
passe correctement

SOLUTION:
Dans les tests de pas faire d'import implicite :
from .models import ItsAdmin
mais
from quotas.models import ItsAdmin
