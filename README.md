# Promoting Docker Images from different OpenShift v4.5 clusters using Tekton CI/CD Pipeline

![IBM](./images/os-logo.jpg?raw=true "IBM")

[Red Hat OpenShift on IBM Cloud]( https://www.ibm.com/cloud/openshift) is an extension of the IBM Cloud Kubernetes Service, where IBM manages an OpenShift Container Platform for you. 

In this tutorial we will use two separate OpenShift v4.5 clusters, that represent the test and production environments. In order to increase security and resilience  as well as to reduce the resource consumption on the OpenShift production cluster, Docker images are built and tested on the OpenShift test cluster using buildah and promoted to OpenShift production cluster using skopeo through a Tekton pipeline.

[Skopeo](https://www.redhat.com/en/blog/skopeo-10-released) is a tool for moving container images between different types of container storages.  It allows you to copy container images between container registries like docker.io, quay.io, and your internal container registry or different types of storage on your local system.

[Tekton Pipelines]( https://developer.ibm.com/videos/what-is-tekton/) is an open source framework used for creating cloud-native continuous integration and continuous delivery (CI/CD) pipelines that run on Kubernetes. Tekton Pipelines was built specifically for container environments, supports the software lifecycle, and uses a serverless approach.

For this tutorial we will use [Strapi](https://strapi.io/) (open source Node.js headless CMS), which we will build, deploy, test and promote in `staging` and `production` environments using Tekton pipeline. The test step from the pipeline is not implemented as it is not the scope of this tutorial. Strapi will be connected to an PostgreSQL database, which we will provision in OpenShift. 

In this tutorial, you will become familiar with Tekton CI/CD pipelines and Image promotion on Red Hat OpenShift 4.5 using Tekton Pipelines.


### The image below illustrates what the OpenShift CI/CD Pipeline design looks like.

![Pipeline Design](images/pipeline-design.png?raw=true "Pipeline Design")

---

## Prerequisites

Before you begin this tutorial, please complete the following steps:

1. Register for an [IBM Cloud account](https://cloud.ibm.com/registration).
2. Create two [OpenShift 4.5 clusters on IBM Cloud](https://cloud.ibm.com/docs/openshift?topic=openshift-openshift_tutorial).


*Optional: Download [Visual Studio Code IDE](https://code.visualstudio.com) for editing the Node.js project.*


## Estimated time 

It should take you approximately 1 hour to provision the OpenShift clusters and to perform this tutorial.  

---

## Steps

1. [Configure OpenShift clusters](#configure-openshift-clusters)
2. [Provision PostgreSQL databases](#provision-postgresql-databases)
3. [Create a cloud-native CI/CD pipeline on OpenShift](#create-a-cloud-native-cicd-pipeline-on-openshift)
4. [Build and promote the image on OpenShift test cluster](#build-and-promote-the-image-on-openshift-test-cluster)
5. [Deploy newly created image on OpenShift production cluster](#deploy-newly-created-image-on-openshift-production-cluster)


It’s also important to know what each Git folder contains: 

* `strapi-app` is the context root of the [Strapi](https://strapi.io/) (Open source Node.js Headless CMS) application.

* `pipelines/stage` contains the [OpenShift Pipeline](https://www.openshift.com/learn/topics/pipelines) implementation and YAML resources for OpenShift test cluster.

* `pipelines/prod` contains the [OpenShift Pipeline](https://www.openshift.com/learn/topics/pipelines) implementation and YAML resources for OpenShift production cluster.


---
![IBM](images/ocp2.png?raw=true "IBM") ![IBM](images/tekton2.jpg?raw=true "IBM")

---

## Configure OpenShift clusters

1. Install the OpenShift Pipelines Operator on both clusters.

Follow the OpenShift documentation on how to install the OpenShift Pipelines Operator from either WebConsole or CLI:

https://docs.openshift.com/container-platform/4.5/pipelines/installing-pipelines.html#op-installing-pipelines-operator-in-web-console_installing-pipelines 

After successful installation, you will have all related Tekton building blocks created in `pipeline` project.

2. Create `ci-env`, `stage-env` and `prod-env` projects. In `ci-env`, you will store the CI/CD pipeline and all pipeline resources. In `stage-env` and `prod-env`, you will deploy the application through image promotion.

On OpenShift `test` cluster :
```
oc config use-context <test-cluster-context>
oc new-project ci-env
oc new-project stage-env
```

On OpenShift `production` cluster :
```
oc config use-context <production-cluster-context>
oc new-project prod-env
```

3.  We will create the Strapi image in OpenShift test cluster and  promote the image in OpenShift production cluster, therefore we need to link these 2 clusters. This is done by generating a serviceaccount login token from the OpenShift production cluster. This token must be saved on OpenShift 
cluster as a secret (eg. os-prod-cluster). Another token muste be generatd for OpenShift test cluster, which will be used for promoting the image using skopeo copy tool.


On OpenShift `production` cluster :
```
oc config use-context <production-cluster-context>
oc project prod-env
token-prod=`oc sa get-token pipeline`
echo $token-prod
oc whoami --show-server=true
```
*Note the pipeline service account token and OpenShift production cluster login URL.

*You will need to edit [task-promote-prod.yaml](pipelines/stage/task-promote-prod.yaml) and update the prodRoute=<route to your OpenShift production cluster> placeholder.


On OpenShift `test` cluster :
```
oc config use-context <test-cluster-context>
oc project ci-env
oc create secret generic os-prod-cluster --from-literal=token=$token-prod
token=`oc sa get-token pipeline`
echo $token
oc create secret generic os-test-cluster --from-literal=token=$token
oc whoami --show-server=true
```
*note the pipeline service account token and OpenShift test cluster login URL.

Now you can use this secrets mounted inside a task pipeline as volume (see file [task-promote-prod.yaml](pipelines/stage/task-promote-prod.yaml))
```
...
  volumes:
    - name: os-token-prod
      secret:
        secretName: os-prod-cluster   
    - name: os-token-test
      secret:
        secretName: os-test-cluster 
...        
```

4. Allow the `pipeline` service account to create resources and make deploys on `stage-env` project:

On OpenShift `test` cluster:

```
oc config use-context <test-cluster-context>
oc adm policy add-scc-to-user privileged system:serviceaccount:ci-env:pipeline -n ci-env
oc adm policy add-scc-to-user privileged system:serviceaccount:ci-env:pipeline -n stage-env
oc adm policy add-role-to-user edit system:serviceaccount:ci-env:pipeline -n ci-env
oc adm policy add-role-to-user edit system:serviceaccount:ci-env:pipeline -n stage-env
```

5. Allow `default` service account to run image as ROOT, because strapi app runs as ROOT.

On OpenShift `test` cluster :
```
oc config use-context <test-cluster-context>
oc adm policy add-scc-to-user anyuid -z default -n stage-env
oc adm policy add-scc-to-user privileged -z default -n stage-env
```

On OpenShift `production` cluster :
```
oc config use-context <production-cluster-context>
oc adm policy add-scc-to-user anyuid -z default -n prod-env
oc adm policy add-scc-to-user privileged -z default -n prod-env
```

---
## Provision PostgreSQL databases

Follow these [instructions](https://docs.openshift.com/container-platform/4.3/applications/service_brokers/provisioning-template-application.html) in order to quickly provision a new PostgreSQL instance in `stage-env` and `prod-env` projects. Use as `Database Service Name` = `postgresql`

![Pipeline Design](images/postgres.png?raw=true "Pipeline Design")

The template will create a new secret called `postgresql` which we will add as environment variable for Strapi (from CI/CD pipeline):
```
oc describe secret postgresql
Name:         postgresql
...
Type:  Opaque

Data
====
database-name:       8 bytes
database-password:  16 bytes
database-user:       7 bytes
```
Check [task-deploy.yaml](pipelines/stage/task-deploy.yaml) :
```
oc set env dc/$(inputs.params.APP_NAME) --from secret/postgresql --overwrite -n $(inputs.params.DEPLOY_PROJECT)
```

---
## Create a cloud-native CI/CD pipeline on OpenShift

OpenShift Pipelines is a cloud-native, continuous integration and continuous delivery (CI/CD) solution based on Kubernetes resources. It uses Tekton building blocks to automate deployments across multiple platforms by abstracting away the underlying implementation details. Tekton introduces a number of standard Custom Resource Definitions (CRDs) for defining CI/CD pipelines that are portable across Kubernetes distributions.

More information can be found here:
https://docs.openshift.com/container-platform/4.5/pipelines/understanding-openshift-pipelines.html



## Create the Tekton CI/CD pipeline

1. Clone or Fork this GitHub project:

```
git clone https://github.com/vladsancira/image-promotion.git
cd image-promotion
```

2. Create Tekton resources, tasks, and a pipeline:

On OpenShift `test` cluster :
```
oc config use-context <test-cluster-context>
oc create -f pipelines/stage -n ci-env
```
On OpenShift `production` cluster :
```
oc config use-context <production-cluster-context>
oc create -f pipelines/prod -n ci-env
```

3. Update promote task with your OpenShift routes [task-promote-prod.yaml](pipelines/stage/task-promote-prod.yaml): 

```
           testRoute=<route to your OpenShift test cluster>
           prodRoute=<route to your OpenShift production cluster>
```

---

## Build and promote the image on OpenShift test cluster

1. Start the CI/CD Pipeline  from OpenShift Pipelines UI under `ci-env` project and wait until pipelinRun is complete :

![IBM](images/strapi-pipeline.png?raw=true "IBM") 


![IBM](images/start-stage-pipeline.png?raw=true "IBM") 


2. Check in the pipelineRun logs that that the Strapi image was promoted (pushed) to the production cluster:

![IBM](images/step-promote.png?raw=true "IBM") 



3. Check the newly Strapi image created in `stage-env` project:

On OpenShift `TEST` cluster :
```
oc config use-context <test-cluster-context>
oc get is strapi -n stage-env 
NAME     IMAGE REPOSITORY                                                       TAGS                              UPDATED
strapi   image-registry.openshift-image-registry.svc:5000/stage-env/strapi   latest,1.0.0   2 minutes ago
```

4. Application is now deployed in `stage-env`.
---

## Deploy newly created image on OpenShift production cluster

1. Check the newly Strapi image pushed from test cluster in `prod-env` project:

On OpenShift `production` cluster :
```
oc config use-context <production-cluster-context>
oc get is strapi -n prod-env 
NAME     IMAGE REPOSITORY                                                       TAGS                              UPDATED
strapi   image-registry.openshift-image-registry.svc:5000/prod-env/strapi   latest,1.0.0   1 minute ago
```

2. Start the CI/CD Pipeline  from OpenShift Pipelines UI under `prod-env` project and wait until pipelinRun is complete :

![IBM](images/start-prod-pipeline.png?raw=true "IBM") 

3. Application is now deployed in `prod-env`

Retrive the access link for strapi application : 
```
oc config use-context <production-cluster-context>
oc get route strapi -n prod-env 
```


![IBM](images/strapi.png?raw=true "IBM") 
---

# Summary 

Congratulations! You have successfully created a cloud-native CI/CD Tekton Pipeline for building, promoting and deploying the Strapi CMS application in OpenShift clusters. 
