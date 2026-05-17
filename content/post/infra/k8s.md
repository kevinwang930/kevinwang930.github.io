---
title: "K8s generals"
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

## Basic Usage (cheat sheet)

```bash
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

## Recommendations

- Use declarative manifests (`kubectl apply -f`) and store them in git.
- Prefer `readinessProbes` and `livenessProbes` for production workloads.
- Use namespaces to separate environments (dev/stage/prod).
- Monitor cluster health (metrics-server, Prometheus) and logs.

If you want, I can add diagrams, sample manifests for a full app (Service+Deployment+PVC), or a short troubleshooting checklist.
