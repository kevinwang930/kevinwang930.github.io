---
title: "Minikube generals"
date: 2026-05-16T22:24:23+02:00
categories:
- infra
- container
tags:
- infra
- container
keywords:
- minikube
#thumbnailImage: //example.com/image.jpg
---

Minikube runs Kubernetes locally in a VM or container. It’s fast, lightweight, and ideal for dev, testing, and learning. 

<!--more-->


## Quick Start

```bash
minikube start                # default
minikube start --driver=docker
minikube start --cpus=4 --memory=8192
minikube status               # check status
kubectl cluster-info          # info
minikube stop                 # stop
minikube delete               # delete
minikube dashboard            # UI
minikube ip                   # get IP
minikube ssh                  # shell
```

**Deploy app:**
```bash
kubectl create deployment hello-minikube --image=kicbase/echo-server:1.0
kubectl expose deployment hello-minikube --type=NodePort --port=8080
kubectl get svc
minikube service hello-minikube
```


## Driver

**Docker:** Fast, low overhead, easy setup, works on Linux/macOS/Windows. Needs Docker running. Best for dev and CI.

```bash
minikube start --driver=docker
```

**KVM:** Full VM isolation, higher resource use, Linux only, slower start, more setup. Best for prod-like tests and strong isolation.

```bash
sudo apt-get install libvirt-clients libvirt-daemon-system
minikube start --driver=kvm2
```

| Feature         | Docker   | KVM     |
|-----------------|----------|---------|
| Startup         | Fast     | Slow    |
| Overhead        | Low      | High    |
| Isolation       | Medium   | Strong  |
| Platforms       | All      | Linux   |
| Setup           | Easy     | Complex |

**Tip:** Use Docker for most cases. Use KVM for strict isolation or prod-like needs on Linux.


## Features

- **Add-ons:**
  ```bash
  minikube addons list
  minikube addons enable ingress
  ```
- **Volumes:**
  ```bash
  minikube mount /local/path:/vm/path
  ```
- **Docker env:**
  ```bash
  eval $(minikube docker-env)
  ```


## Use Cases
- App dev
- Learn/test k8s
- Debug configs
- CI/CD pipeline



## Persisting Data Across Restarts

Quick: mount a host dir into Minikube, then expose it to Kubernetes via a PV/PVC. `--mount` makes the host path visible inside Minikube; Kubernetes needs a PV to claim it.

Commands:

```bash
mkdir -p /data/pv1
minikube start --driver=docker --mount --mount-string="/data/pv1:/data/pv1"
```

PV and PVC (use `pv.yaml` and `pvc.yaml`):

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-hostpath
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data/pv1
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-hostpath
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Example Deployment using the PVC (`deploy-with-pvc.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-pv
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-pv
  template:
    metadata:
      labels:
        app: nginx-pv
    spec:
      containers:
      - name: nginx
        image: nginx:stable
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: pvc-hostpath
```

Apply and verify:

```bash
kubectl apply -f pv.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deploy-with-pvc.yaml
kubectl get pv,pvc
kubectl get pods
```

Notes:
- If `/data/pv1` is a host directory (mounted with `--mount` or a hostPath that points to the real host), the host files persist after `minikube stop`, `minikube start`, and even after `minikube delete` — Minikube does not remove host directories. If the path is inside the Minikube VM (not a host mount), `minikube delete` removes the VM and that data.
- Ensure host permissions (`chown`) so the container can write the directory.
- On SELinux systems, you may need `chcon -Rt svirt_sandbox_file_t /data/pv1`.
- For CI or ephemeral setups prefer Docker driver mounts; for stricter isolation prefer KVM with a remote storage solution.


