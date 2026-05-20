---
title: "Kubernetes generals"
date: 2026-05-17T12:58:16+02:00
categories:
- infra
- container
tags:
- infra
- container
keywords:
- k8s
- kubernetes
#thumbnailImage: //example.com/image.jpg
---



Kubernetes (k8s) is a container orchestration system that automates deployment, scaling, and management of containerized applications.
<!--more-->
## Architecture Overview

- **Control Plane**: manages cluster state and scheduling.
	- `kube-apiserver`: API front end (single source of truth).
	- `etcd`: key-value store for cluster state.
	- `kube-scheduler`: assigns pods to nodes.
	- `kube-controller-manager`: runs controllers (replication, endpoints, nodes).
	- `cloud-controller-manager` (optional): cloud-provider integration.

- **Nodes (Worker Plane)**: run workloads.
	- `kubelet`: agent that manages pods on a node.
	- `kube-proxy`: implements Service networking (iptables/ipvs).
	- Container runtime: `containerd`, `docker`, or CRI-compatible runtime.

- **Add-ons / Services**
	- DNS (CoreDNS), ingress controllers, metrics-server, network plugins (CNI).

## Key Concepts

- **Pod**: smallest deployable unit (one or more containers sharing network and storage).
- **Deployment**: declarative updates for Pods and ReplicaSets.
- **Service**: stable network endpoint exposing Pods.
- **ConfigMap / Secret**: configuration and sensitive data.
- **PersistentVolume (PV) / PersistentVolumeClaim (PVC)**: storage abstraction.
- **Namespace**: virtual cluster partitioning.
- **Context**: a context is a set of access parameters that tells kubectl which cluster to talk to, which user to authenticate as, and which namespace to use by default

## Basic Usage 

```bash
# contexts (view and switch)
kubectl config get-contexts                # list contexts
kubectl config current-context             # show current context
kubectl config use-context <context-name>  # switch context

# namespaces
kubectl get namespaces                      # list namespaces
kubectl create namespace <name>             # create namespace
kubectl delete namespace <name>             # delete namespace
kubectl config set-context --current --namespace=<name>  # set default namespace for current context

# see cluster state
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# deploy an app
kubectl create deployment myapp --image=nginx:stable
kubectl expose deployment myapp --port=80 --type=ClusterIP

# scale
kubectl scale deployment/myapp --replicas=3

# update image
kubectl set image deployment/myapp myapp=nginx:1.24

# inspect and debug
kubectl describe pod <pod>
kubectl logs deployment/myapp
kubectl exec -it <pod> -- /bin/sh

# persistent storage example
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
	name: example-pv
spec:
	capacity:
		storage: 1Gi
	accessModes:
		- ReadWriteOnce
	hostPath:
		path: /tmp/data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
	name: example-pvc
spec:
	accessModes:
		- ReadWriteOnce
	resources:
		requests:
			storage: 1Gi
EOF
```

## Helm (package manager)

- Helm is the Kubernetes package manager. Charts package and templatize manifests so apps deploy reproducibly.

Install on Fedora:

```bash
# install from Fedora repos (preferred)
sudo dnf install -y helm


Quick commands:

```bash
# add a chart repo and update
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# search and install
helm search repo nginx
helm install my-nginx bitnami/nginx -f values.yaml

# manage releases
helm list
helm upgrade my-nginx bitnami/nginx -f values.yaml
helm rollback my-nginx 1
helm uninstall my-nginx

# inspect and render
helm get values my-nginx
helm template my-nginx bitnami/nginx
helm lint ./chart
```
