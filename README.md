# XAAS-ADMIN

## Local install

This procedure assumes that "docker" is already installed.

1. You have to start by cloning current repository.
    > git@github.com:epfl-idevelop/xaas-admin.git

1. Then, start the configuration process
    > make config
    
1. This will create a `.env` file that you'll have to edit to configure correct information
For local execution, values are "free" but the following needs to be set with specified values:
    ```
    MYSQL_HOST=xaas-mariadb
    MYSQL_PORT=3306
    ```
     
1. Once all values have been set, start docker images build
    > make build
    
1. Start install procedure. This will :
    * create all Django tables in DB
    * create a super user with the information you'll be asked for.
    > make install
    
1. Once install is over, all containers will restart to load new configuration.

1. Check that all 3 containers are running.
    > docker ps
    
    You have to see:
    * xaas-nginx
    * xaas-django
    * xaas-mariadb 

See below for rest of procedure...


## Local execution

1. Start by performing "install" procedure explained above. If you just did it, go to point 3.

1. If "install" procedure was done in the past and containers are not running, start them.
    > make up
    
    **Note** If you need to debug something because a container is crashing, you can use:
    > make up-debug
    
    This will display a trace for each container in the same terminal and you'll be able to see what happens.

1. You can now connect on Django administration: <https://localhost/admin> .
    You'll be prompted for a Tequila authentication. Then you'll be redirected using 
    HTTPS so it will leads to an error. Just change "https" to "http" and this will work.
 
    
## Fresh install

If you want to do a fresh install of you environment (without touching `.env` file), just execute
> make clean-all

After this, you'll have to go through "Local install" procedure again.


## Tips
* As explained before, you can start containers in debug mode using :
    > make up-debug

* You can go in Django (xaas-django) or MariaDB (xaas-mariadb) containers if you want to check something, just use:
    
    **Django**
    > make exec-django
    
    **MariaDB**
    > make exec-mariadb

* It is possible to import information in DB from a SQL file, just use:
    > make import-sql SQL_FILE=&lt;pathToFile&gt;