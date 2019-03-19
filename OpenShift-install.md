# XaaS-Admin on Openshift

This documentation explain how to "transform" the Docker application to run on 
Openshift.

## Procedure

### Install Kompose

Follow documentation on <http://kompose.io/installation/> to install Kompose

### Create necessary files for OpenShift

1. Using a Terminal, go in folder where your `docker-compose.yml` file is located
1. Create files for OpenShift. It will create some files in the same directory:
    > kompose --provider=openshift --build build-config --build-repo=https://github.com/epfl-idevelop/xaas-admin.git convert

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


### Configure vars




### Add superuser

If there is still no superuser defined, we have to create one.

1. Go in **Applications > Pods**

1. Click on the running **xaas-django-...**

1. On the top, click on **Terminal** to go inside container.

1. Enter the following commands to create a superuser:
```
bash
_utils/create-admins.sh

```

1. Follow instructions



-- Astuce:
-- Ajout env var BUILD_LOGLEVEL avec 2 ou 3 comme valeur



 




