Probleme 1
-----------

tests: pour une raison que j'ignore, je ne parviens pas à exécuter la commande :
python src/manage.py test
qui crash
mais par contre
python src/manage.py test quotas
passe correctement

SOLUTION:
Dans les tests ne pas faire d'import implicite :
from .models import ItsAdmin
mais
from quotas.models import ItsAdmin

Probleme 2
----------
Sur le serveur de test SELinux semble nous embêter lors de la commande :

pip install -r /var/www/vhosts/parking.epfl.ch/private/requirements/test.txt

out: /home/kis/xaas-admin/bin/python3: error while loading shared libraries: libpython3.5m.so.rh-python35-1.0: cannot open shared object file: No such file or directory

j'ai tenté :
chcon -t httpd_sys_script_exec_t /opt/rh/rh-python35/root/usr/lib64/libpython3.5m.so.rh-python35-1.0
chcon: failed to change context of ‘/opt/rh/rh-python35/root/usr/lib64/libpython3.5m.so.rh-python35-1.0’ to ‘system_u:object_r:httpd_sys_script_exec_t:s0’: Operation not permitted