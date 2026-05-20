---
title: "Spark architecture & Kubernetes"
date: 2026-05-17T13:30:00+02:00
draft: true
categories:
- data
- calculation
tags:
- spark
- kubernetes
keywords:
- spark
- bigdata
- kubernetes
#thumbnailImage: //example.com/image.jpg
---

Apache Spark — architecture, quick usage, and deploying on Kubernetes.

<!--more-->

## Architecture 

- **Driver**: coordinates the application, creates tasks, schedules work.
- **Executors**: JVM processes on worker nodes that run tasks and hold data in memory.
- **Cluster manager**: allocates resources to driver/executors (YARN, Mesos, Kubernetes, Standalone).
- **Task**: unit of work scheduled by the driver and executed on executors.
- **Spark UI**: web UI for jobs/stages/tasks and storage/executor metrics.

Typical flow: Driver -> requests executors from cluster manager -> executors run tasks -> results returned to driver or written to storage.

## Quick Usage

- Local mode (development):
```bash
spark-submit --master local[4] --class org.apache.spark.examples.SparkPi spark-examples.jar 100
```
- Cluster mode (production): submit to cluster manager (YARN/Standalone/Kubernetes).
- Common APIs: RDD, DataFrame, Dataset, Structured Streaming.

## Deployment in K8s

Two  approaches:
- Use `spark-submit` in Kubernetes cluster mode (Spark's native K8s support).
- Use the Spark Operator (CRD) to manage `SparkApplication` resources.

Prerequisites:
- A running Kubernetes cluster and `kubectl` configured
- A Spark Docker image (official or custom) accessible to the cluster
- (Optional) Spark Operator installed for CRD usage

### spark-submit (cluster mode)

Example `spark-submit` (cluster deploy):

```bash
# build or pull an image with Spark and your app
# example: use 'gcr.io/spark-image:3.4.0'

spark-submit \
  --master k8s://https://$KUBERNETES_MASTER:6443 \
  --deploy-mode cluster \
  --name spark-pi \
  --class org.apache.spark.examples.SparkPi \
  --conf spark.executor.instances=2 \
  --conf spark.kubernetes.namespace=default \
  --conf spark.kubernetes.container.image=gcr.io/myrepo/spark:3.4.0 \
  local:///opt/spark/examples/jars/spark-examples_2.12-3.4.0.jar 100
```

Notes:
- `spark.kubernetes.container.image` must exist in the cluster (private registries require imagePullSecrets).
- `local:///...` refers to files baked into the image; use remote jars/URLs otherwise.

### Spark Operator (recommended for production)

Install Spark Operator (Helm or manifest). Then create a `SparkApplication` CRD.

YAML example (`sparkapp.yaml`):

```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: spark-pi
  namespace: default
spec:
  type: Scala
  mode: cluster
  image: gcr.io/myrepo/spark:3.4.0
  imagePullPolicy: Always
  mainClass: org.apache.spark.examples.SparkPi
  mainApplicationFile: local:///opt/spark/examples/jars/spark-examples_2.12-3.4.0.jar
  sparkVersion: "3.4.0"
  driver:
    cores: 1
    memory: 512m
    serviceAccount: spark
  executor:
    cores: 1
    instances: 2
    memory: 512m
```

Commands to apply and watch:

```bash
# (1) create service account and RBAC if needed (Operator docs provide exact manifests)
kubectl apply -f sparkapp.yaml
kubectl get sparkapplications -n default -w
kubectl logs -l spark-role=driver -n default --tail=200
```

## Tips & Caveats

- Use small images that contain both Spark and your application JAR (or use remote jars).
- Tune `spark.executor.instances`, cores, and memory to fit cluster capacity.
- Configure `spark.kubernetes.authenticate.driver.serviceAccountName` or `serviceAccount` in SparkApplication for permissions.
- For production, prefer the Spark Operator for lifecycle management (retries, monitoring, history integration).
- Monitor Spark UI (driver pod) and Kubernetes events for failures.


<!--more-->
