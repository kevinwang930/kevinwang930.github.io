---
title: "K3s generals"
date: 2026-05-17T12:20:28+02:00
categories:
- infra
- container
tags:
- infra
- container
keywords:
- k3s
#thumbnailImage: //example.com/image.jpg
---

K3s is a lightweight Kubernetes distribution. Minimal footprint, single binary, stripped of non-essential components. Perfect for edge, IoT, and local dev. Fast startup, minimal memory.

<!--more-->

## What is K3s?

K3s is a certified Kubernetes distribution by Rancher Labs. It's a stripped-down, production-grade Kubernetes for resource-constrained environments.

**Key differences from full Kubernetes:**
- Single binary, easy installation
- Embedded etcd (no separate control plane complexity)
- Supports kubectl natively
- ~40-50MB binary size vs. 1GB+ for full Kubernetes
- 512MB RAM minimum vs. 1-2GB for standard Kubernetes
- Removed non-essential features (alpha APIs, legacy auth)

**Best for:**
- Local development
- Edge computing, IoT devices
- CI/CD runners
- Rapid Kubernetes testing
- Minimal resource environments

## Installation on Fedora

**SELinux policy (required on Fedora):**
```bash
# Install container runtime SELinux policies
sudo dnf install -y container-selinux selinux-policy-base policycoreutils-python-utils

# Install k3s SELinux tracking policy
sudo dnf install -y https://rpm.rancher.io/k3s/latest/common/fedora/44/noarch/k3s-selinux-1.6-1.fc44.noarch.rpm
```

**Install k3s:**
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--selinux" sh -
sudo systemctl status k3s
```

**Access kubeconfig:**
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# persist
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
```

**Verify installation:**
```bash
kubectl cluster-info
kubectl get nodes
```

## Quick Start

**Check cluster:**
```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

**Deploy an app:**
```bash
kubectl create deployment hello-k3s --image=kicbase/echo-server:1.0
kubectl expose deployment hello-k3s --type=LoadBalancer --port=8080
kubectl get svc
```

**Access the service:**
```bash
kubectl port-forward svc/hello-k3s 8080:8080
# Then visit http://localhost:8080
```

**Control k3s service:**
```bash
sudo systemctl stop k3s
sudo systemctl start k3s
sudo systemctl restart k3s
sudo systemctl status k3s
sudo systemctl enable k3s  # auto-start on reboot
```

**Uninstall k3s:**
```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

## K3s vs Minikube

| Feature | K3s | Minikube |
|---------|-----|----------|
| Size | ~40-50MB | 100MB+ |
| Memory | 512MB min | 2GB+ recommended |
| Setup | Single command | CLI + drivers |
| Persistence | Native support | Via mounts |
| Use case | Edge, prod-like | Local dev/testing |
| Start speed | Fast | Moderate |

**Use K3s for:** production-like testing, low-resource dev, edge simulation.  
**Use Minikube for:** learning, isolated local testing.

## Local Dev Setup on Fedora

**Create data directory:**
```bash
mkdir -p ~/k3s-data
sudo chown -R 1000:1000 ~/k3s-data
sudo semanage fcontext -a -t svirt_sandbox_file_t "$HOME/k3s-data(/.*)?"
sudo restorecon -Rv ~/k3s-data
```

**Configure kubeconfig:**
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

**Persistent storage with hostPath:**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: fedora-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: $HOME/k3s-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fedora-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

**Deploy with persistent volume:**
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dev-app
  template:
    metadata:
      labels:
        app: dev-app
    spec:
      containers:
      - name: app
        image: nginx:stable
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: fedora-pvc
EOF
```

**Monitor:**
```bash
kubectl get pods -w
kubectl logs -f deployment/dev-app
kubectl describe pod <pod-name>
```

## Tips

- On Fedora, install k3s-selinux package to handle SELinux contexts automatically.
- K3s removes alpha APIs; standard Kubernetes may be needed for them.
- Use port-forward or LoadBalancer service to expose apps locally.
- K3s embedded etcd is suitable for dev; use external etcd for HA.
- Run `sudo systemctl enable k3s` to auto-start on reboot.
- Run `sudo systemctl enable k3s` to auto-start on reboot.
