# XaaS-Admin on Openshift

This documentation explain how to "transform" the Docker application to run on 
Openshift.

## Procedure

### Install Kompose

Follow documentation on <http://kompose.io/installation/> to install Kompose

### Install OC (OpenShift command line tool)

For some operation, we will need OpenShift command line tool so we have to install it.

1. Download package for your operating system. You can found it at bottom of following
page <https://github.com/openshift/origin/releases/latest>

1. If you're running on Linux, extract the file, put it at the right place and add the rights to execute it :
    ```
    tar -xvf openshift-origin-client-tools-*
    cd openshift-origin-client-tools-*
    sudo mv oc /usr/local/bin/
    sudo chmod a+x /usr/local/bin/oc
    ```
    

### Create necessary files for OpenShift

1. Using a Terminal, go in folder where your `docker-compose.yml` file is located
1. Create files for OpenShift. It will create some files in the same directory:
    ```
    kompose --provider=openshift --build build-config --build-repo=https://github.com/epfl-idevelop/xaas-admin.git convert
    ```

1. This will create some files starting with "xaas-*". 

### Modify generated files for OpenShift

Some of generated YAML files need to be modified to fit OpenShift prerequisites
- xaas-django-buildconfig.yaml
- xaas-django-deploymentconfig.yaml

C2C put limits on resource that can be used, so we have to fix some limits in `*-buildconfig.yaml` files.

1. Modify resources in `xaas-django-buildconfig.yaml`.
    ```
    spec -> resources: {}
    ```
    to
    ```
      resources: 
        requests:
          cpu: "50m"
          memory: "200Mi"
        limits:
          cpu: "100m"
          memory: "400Mi"
    ```

1. Modify resources `xaas-django-deploymentconfig.yaml` (two locations )
    ```
    spec -> strategy -> resources: {}
    spec -> template -> spec -> containers -> envFrom -> resources: {}
    ```
    to
    ```
      resources: 
        requests:
          cpu: "50m"
          memory: "200Mi"
        limits:
          cpu: "100m"
          memory: "400Mi"
    ```

1. You will also have to remove all references to volumes in `xaas-django-deploymentconfig.yaml` because we won't use them on OpenShift.
    ```
        volumeMounts:
          - mountPath: /usr/src/xaas-admin
            name: xaas-django-claim0
    ```
    and
    ```
        volumes:
          - name: xaas-django-claim0
            persistentVolumeClaim:
              claimName: xaas-django-claim0
    
    ```

### Create elements on OpenShift

**Service**

1. Connect on OpenShift web console (<https://pub-os-exopge.epfl.ch>) 

1. Select projet **iaas-test**

1. Go in **Applications > Services** 

1. On the top right, click on **Add to Project** and select **Import YAML/JSON** 

1. A modal window will open. You can now copy/past content of `xaas-django-service.yaml` or click on **Browse...** and just upload it.

1. Then click on **Create**.


**Image**

1. Next step is to create an "Image Stream". Go in *Builds > Images*

1. On the top right, click on **Add to Project** and select **Import YAML/JSON**
 
1. A modal window will open. You can now copy/past content of `xaas-django-imagestream.yaml` or click on **Browse...** and just upload it.

1. Then click on **Create**.


**Build**

1. And now, the "Build", go in **Builds > Builds**

1. On the top right, click on **Add to Project** and select **Import YAML/JSON**
 
1. A modal window will open. You can now copy/past content of `xaas-django-buildconfig.yaml` or click on **Browse...** and just upload it.

1. Then click on **Create**.

1. The build will automatically start but may fail because build argument is incorrect.
Go in **Builds > Builds > xaas-django** and click on **Environment**

1. Modify last part of `DJANGO_SETTINGS_MODULE` to replace "local" with "test" or "prod" depending environment on which you're deploying the app. 


**Deployment**

1. Finally, the "Deployment", go in **Applications > Deployments**

1. On the top right, click on **Add to Project** and select **Import YAML/JSON**
 
1. A modal window will open. You can now copy/past content of `xaas-django-deploymentconfig.yaml` or click on **Browse...** and just upload it.

1. Then click on **Create**.

1. Now we will have to edit environment variables for deployment because content 
present in `xaas-django-deploymentconfig.yaml` has been taken from the local environment
where the file has been created. So, it won't fit OpenShift environment.

1. Go in **Applications > Deployments** and click on **xaas-django**

1. On the top click on **Environment** and edit the values if needed, especially 
database connection information.

    **Note:** value `DJANGO_SETTINGS_MODULE` needs to be identical as the one defined above 
in the build configuration.
  

### Add superuser

**NOTE:** If you plan to import a full DB backup, you can skip this step because users
will also be imported in database. See below for procedure to import data in database.

If there is still no superuser defined, we have to create one.
**!!!BE CAREFUL TO DO THIS BEFORE TRYING FIRST CONNECTION ON DJANGO!!!**

1. Go in **Applications > Pods**

1. Click on the running **xaas-django-...**

1. On the top, click on **Terminal** to go inside container.

1. Enter the following commands to create a superuser:
    ```
    bash
    _utils/create-admins.sh
    
    ```

1. Follow instructions


### Import data in Database

A script has been written to allow to import an entire SQL file in the database.

First, we will have to copy *.sql file into container. For this, we will use `oc` command 
(OpenShift command line tool).

1. Run a terminal and connect on OpenShift portal.
    ```
    oc login https://pub-os-exopge.epfl.ch
    ```

1. Current project will be display right after login. If needed, you can change to another one using:
    ```
    oc project <projectName>
    ```
    
1. Once you're on the correct project, you'll have to get current running POD name.
    ```
    $ oc get pods
    
    NAME                   READY     STATUS      RESTARTS   AGE
    xaas-django-1-build    0/1       Error       0          4d
    xaas-django-2-build    0/1       Error       0          4d
    xaas-django-28-b4wnj   1/1       Running     0          7m
    xaas-django-3-build    0/1       Completed   0          4d
    xaas-django-4-build    0/1       Completed   0          4d
    xaas-django-5-build    0/1       Completed   0          4d
    xaas-django-6-build    0/1       Completed   0          22h
    xaas-django-7-build    0/1       Completed   0          10m
    ```
    For this example, we will use the only one un "Running" status => "xaas-django-28-b4wnj"

1. Copy the *.sql file into container.
    ```
    oc cp </path/to/local/file.sql> <podName>:/tmp/file.sql
    ```

1. Once the file has ben copied on the POD, you can go in OpenShift web console.

1. Go in **Applications > Pods**

1. Click on the running **xaas-django-...**

1. On the top, click on **Terminal** to go inside container.

1. Enter in bash mode and run SQL import.
    ```
    bash
    _utils/import-sql.sh /tmp/file.sql
    ```

1. At the end, don't forget to remove *.sql file

## Tips

- If build is failing, you can add an env var named `BUILD_LOGLEVEL` with `3` as value 
and it will display errors during build to diagnose what's wrong. 



 




