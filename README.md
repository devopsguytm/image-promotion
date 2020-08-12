# Create a CI/CD Tekton Pipeline for building, promoting & deploying Strapi (Open source Node.js Headless CMS) in OpenShift 4.3 

![IBM](./images/os-logo.jpg?raw=true "IBM")

[Red Hat OpenShift on IBM Cloud]( https://www.ibm.com/cloud/openshift) is an extension of the IBM Cloud Kubernetes Service, where IBM manages an OpenShift Container Platform for you. 

[Tekton Pipelines]( https://developer.ibm.com/videos/what-is-tekton/) is an open source framework used for creating cloud-native continuous integration and continuous delivery (CI/CD) pipelines that run on Kubernetes. Tekton Pipelines was built specifically for container environments, supports the software lifecycle, and uses a serverless approach.

Usually, projects are using separate OpenShift 4 clusters for TEST and PRODUCTION. In order to reduce the resource consumption on the PRODUCTION cluster, Docker images are built on the TEST cluster using `buildah` and promoted to PRODUCTION cluster using `skopeo` through a Tekton pipeline.

In this tutorial, you will become familiar with CI/CD pipelines and Image promotion on Red Hat OpenShift 4.3 using Tekton Pipelines.


## Prerequisites

Before you begin this tutorial, please complete the following steps:

1. Register for an [IBM Cloud account](https://cloud.ibm.com/registration).
2. Create two [OpenShift 4.3 clusters on IBM Cloud](https://cloud.ibm.com/docs/openshift?topic=openshift-openshift_tutorial).


*Optional: Download [Visual Studio Code IDE](https://code.visualstudio.com) for editing the Node.js project.*



## Estimated time 

It should take you approximately 1-2 hour to provision the OpenShift clusters and to perform this tutorial.  

---

## Steps

1. [Configure OpenShift clusters](#configure-openshift-clusters)
2. [Create a cloud-native CI/CD pipeline on OpenShift](#create-a-cloud-native-cicd-pipeline-on-openshift)
3. [Build and promote the image on TEST cluster](#build-and-promote-the-image-on-test-cluster)
4. [Deploy newly created image on PROD cluster](#deploy-newly-created-image-on-prod-cluster)


It’s also important to know what each Git folder contains: 

* `strapi-app` is the context root of the Strapi application.

* `pipelines/stage` contains the [OpenShift Pipeline](https://www.openshift.com/learn/topics/pipelines) implementation and YAML resources for TEST cluster.

* `pipelines/prod` contains the [OpenShift Pipeline](https://www.openshift.com/learn/topics/pipelines) implementation and YAML resources for PRODUCTION cluster.


---
![IBM](images/ocp2.png?raw=true "IBM") ![IBM](images/tekton2.jpg?raw=true "IBM")

---

## Configure OpenShift clusters

1.  We will create the strapi image in OCP TEST cluster and  promote the image in OCP PROD cluster, therefore we need to link these 2 clusters. This is done by generating a serviceaccount login token from the PROD cluster. This token must be saved on TEST cluster as a secret (eg. os-prod-cluster). Another token muste be generatd for TEST cluster, which will be used for promoting the image using `skopeo` copy tool.

Skopeo is a tool for moving container images between different types of container storages.  It allows you to copy container images between container registries like docker.io, quay.io, and your internal container registry or different types of storage on your local system.

https://www.redhat.com/en/blog/skopeo-10-released

On `PRODUCTION` cluster :
```
oc project prod-env
token-prod=`oc sa get-token pipeline`
echo $token-prod
oc whoami --show-server=true
```
*note the pipeline service account token and PROD cluster login URL.

On `TEST` cluster :
```
oc project ci-env
oc create secret generic os-prod-cluster --from-literal=token=$token-prod
token=`oc sa get-token pipeline`
echo $token
oc create secret generic os-test-cluster --from-literal=token=$token
```

Now you can use this secrets mounted inside a task pipeline as volume (see file `pipelines/prod/task-promote-prod.yaml`)


2. Install the OpenShift Pipelines Operator on both clusters.

Follow the OpenShift documentation on how to install the OpenShift Pipelines Operator from either WebConsole or CLI:

https://docs.openshift.com/container-platform/4.4/pipelines/installing-pipelines.html#op-installing-pipelines-operator-in-web-console_installing-pipelines 

After successful installation, you will have all related Tekton building blocks created in `pipeline` project.

3. Create `ci-env`, `stage-env` and `prod-env` projects. In `ci-env`, you will store the CI/CD pipeline and all pipeline resources. In `stage-env` and `prod-env`, you will deploy the application through image promotion.

On `TEST` cluster :
```
oc new-project ci-env
oc new-project stage-env
```

On `PRODUCTION` cluster :
```
oc new-project prod-env
```

4. Allow the `pipeline` ServiceAccount to create resources and make deploys on `stage-env` project:

On `TEST` cluster:

```
oc adm policy add-scc-to-user privileged system:serviceaccount:ci-env:pipeline -n ci-env
oc adm policy add-scc-to-user privileged system:serviceaccount:ci-env:pipeline -n stage-env
oc adm policy add-role-to-user edit system:serviceaccount:ci-env:pipeline -n ci-env
oc adm policy add-role-to-user edit system:serviceaccount:ci-env:pipeline -n stage-env
```

5. Allow default ServiceAccount to run image as ROOT, because Strapi app runs as ROOT.

On `TEST` cluster :
```
oc adm policy add-scc-to-user anyuid -z default -n stage-env
oc adm policy add-scc-to-user privileged -z default -n stage-env
```

On `PRODUCTION` cluster :
```
oc adm policy add-scc-to-user anyuid -z default -n prod-env
oc adm policy add-scc-to-user privileged -z default -n prod-env
```
---
### The image below illustrates what the OpenShift Pipeline design looks like.

![Pipeline Design](images/pipeline-design.png?raw=true "Pipeline Design")

---
## Create a cloud-native CI/CD pipeline on OpenShift

`OpenShift Pipelines` is a cloud-native, continuous integration and continuous delivery (CI/CD) solution based on Kubernetes resources. It uses Tekton building blocks to automate deployments across multiple platforms by abstracting away the underlying implementation details. Tekton introduces a number of standard Custom Resource Definitions (CRDs) for defining CI/CD pipelines that are portable across Kubernetes distributions.

More information can be found here:
https://docs.openshift.com/container-platform/4.4/pipelines/understanding-openshift-pipelines.html



## Create the Tekton CI/CD pipeline

1. Clone the Git project:

```
git clone https://github.com/vladsancira/image-promotion.git
cd image-promotion
```

If you use IBM GitHub Private Repo then you need to perform these steps :

* create the GitHub Access token for your GitHub account from https://github.ibm.com/settings/tokens
* add read rights to GIT repo for this token
* create an OpenShift secret to store the credentials (username & token)
```
oc create secret generic github-access-token --from-literal username=<github_user> --from-literal password=<github_token> -n ci-env 
```

* addnotate this secret to be used on https://github.ibm.com
```
oc patch secret github-access-token --patch '{"metadata":{"annotations":{"tekton.dev/git-0":"https://github.ibm.com"}}}' -n ci-env
```
* link the secret to pipeline ServiceAccount from ci-env project
```
oc secrets link pipeline github-access-token -n ci-env
```

2. Create Tekton resources, tasks, and a pipeline:

On `TEST` cluster :
```
cd pipeline/stage
oc create -f resources.yaml          -n ci-env
oc create -f task-build.yaml         -n ci-env
oc create -f task-deploy.yaml        -n ci-env
oc create -f task-test.yaml          -n ci-env
oc create -f task-promote-prod.yaml  -n ci-env
oc create -f pipeline.yaml           -n ci-env
```
On `PRODUCTION` cluster :
```
cd pipeline/prod
oc create -f task-deploy.yaml        -n prod-env
oc create -f pipeline.yaml           -n prod-env
```

3. Update promote task with your OpenShift routes `pipelines/stage/task-promote-prod.yaml`: 

```
           testRoute=<route to your OpenShift TEST cluster>
           prodRoute=<route to your OpenShift PRODUCTION cluster>
```

---

## Build and promote the image on TEST cluster

1. Start the CI/CD Pipeline  from OpenShift Pipelines UI under `ci-env` project and wait until PipelinRun is complete :

![IBM](images/strapi-pipeline.png?raw=true "IBM") 


![IBM](images/start-stage-pipeline.png?raw=true "IBM") 


2. Check the PipelineRun that the image was promoted :

![IBM](images/step-promote.png?raw=true "IBM") 



3. Check the newly Strapi image created in `stage-env` project:

On `TEST` cluster :
```
oc get is strapi -n stage-env 
NAME     IMAGE REPOSITORY                                                       TAGS                              UPDATED
strapi   image-registry.openshift-image-registry.svc:5000/stage-env/strapi   latest,1.0.0   2 minutes ago
```

4. Application is now deployed in `stage-env`.
---

## Deploy newly created image on PROD cluster

1. Check the newly Strapi image pushed from TEST cluster in `prod-env` project:

On `PRODUCTION` cluster :
```
oc get is strapi -n prod-env 
NAME     IMAGE REPOSITORY                                                       TAGS                              UPDATED
strapi   image-registry.openshift-image-registry.svc:5000/prod-env/strapi   latest,1.0.0   1 minute ago
```

2. Start the CI/CD Pipeline  from OpenShift Pipelines UI under `prod-env` project and wait until PipelinRun is complete :

![IBM](images/start-prod-pipeline.png?raw=true "IBM") 

3. Application is now deployed in `prod-env`.

---

# Summary 

Congratulations! You have successfully created a cloud-native CI/CD Tekton Pipeline for building, promoting abd deploying the Strapi application in OpenShift clusters. 
