# Redis Visitor Counter

## Run Locally (Docker)

### Start Redis
```
docker run -d --name redis redis:7-alpine
```

### Build the App
```
docker build -t visitor-app .
```

### Run App (with --link)
```
docker run -d --name visitor-app --link redis:redis -p 3000:3000 visitor-app
```

### Or Use Docker Network
```
docker network create visitor-net
docker run -d --name redis --network visitor-net redis:7-alpine
docker run -d --name visitor-app --network visitor-net -p 3000:3000 visitor-app
```

### Visit in Browser
http://localhost:3000

## Push to Docker Hub

```
docker login -u <username>
docker tag visitor-app <username>/visitor-app:latest
docker push <username>/visitor-app:latest
```

## Infrastructure (EKS)

```
terraform init
terraform apply

terraform output eks_admin_user_access_key_id
terraform output eks_admin_user_secret_access_key
terraform output cluster_endpoint

aws eks update-kubeconfig --name my-eks-cluster --region ap-southeast-1
kubectl get nodes
```

## Deploy App on EKS

### Using kubectl
```
kubectl apply -f manifest/deployment.yaml
kubectl get svc | grep visitor-app
kubectl delete -f manifest/deployment.yaml
```

### Using Helm
```
helm upgrade --install visitor-app ./chart \
  --namespace dev \
  --create-namespace \
  -f ./chart/values.yaml

helm uninstall visitor-app-dev -n dev
```

## Outputs

```
cluster_endpoint = "https://<>.ap-southeast-1.eks.amazonaws.com"
eks_admin_user_access_key_id = "<>"
eks_admin_user_arn = "arn:aws:iam::<>:user/eks-admin-user"
eks_admin_user_secret_access_key = <sensitive>
vpc_id = "vpc-<>"
```

## Scaling

### Metrics Server for HPA (Scale pods based on actual resource usage (CPU/Memory)
```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Cluster Autoscaler with Helm (Scale nodes based on unschedulable pods)
```
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=my-eks-cluster \
  --set awsRegion=ap-southeast-1 \
  --set rbac.create=true \
  --set serviceAccount.create=false \
  --set serviceAccount.name=cluster-autoscaler-aws-cluster-autoscaler \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::<>:role/cluster-autoscaler-irsa" \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set extraArgs.expander=least-waste \
  --set extraArgs.logtostderr=true \
  --set extraArgs.stderrthreshold=info
```

# EKS Infrastructure Summary - Terraform

## 1. Provider & Region

| Key | Value |
|-----|-------|
| `provider` | `aws` |
| `region` | `ap-southeast-1` |

---

## 2. VPC Configuration

| Resource | Value |
|----------|-------|
| VPC CIDR | `55.0.0.0/16` |
| DNS Support | Enabled |
| DNS Hostnames | Enabled |
| Tag | `Name = eks-vpc` |

---

## 3. Subnets

### Public Subnets (One per AZ)
| Subnet Index | CIDR Block | Notes |
|--------------|------------|-------|
| `0` | `55.0.1.0/24` | Mapped to first AZ |
| `1` | `55.0.2.0/24` | Mapped to second AZ |
| `2` | `55.0.3.0/24` | Mapped to third AZ |
| Tags | `eks-public-0`, `eks-public-1`, `eks-public-2` |

### Private Subnets (One per AZ)
| Subnet Index | CIDR Block | Notes |
|--------------|------------|-------|
| `0` | `55.0.101.0/24` | Mapped to first AZ |
| `1` | `55.0.102.0/24` | Mapped to second AZ |
| `2` | `55.0.103.0/24` | Mapped to third AZ |
| Tags | `eks-private-0`, `eks-private-1`, `eks-private-2` |

---

## 4. Internet & NAT Gateways

| Resource | Quantity | Notes |
|----------|----------|-------|
| Internet Gateway | 1 | Attached to VPC |
| NAT Gateway | 3 | One per AZ (each mapped to a public subnet) |
| EIPs | 3 | One per NAT Gateway |

---

## 5. Route Tables

### Public
- 1 shared route table for all public subnets
- Routes `0.0.0.0/0` → Internet Gateway

### Private
- 3 route tables (one per private subnet)
- Routes `0.0.0.0/0` → corresponding NAT Gateway

---

## 6. EKS Cluster

| Key | Value |
|-----|-------|
| Cluster Name | `my-eks-cluster` |
| Subnet Type | Private only |
| Endpoint Access | Public only |
| Security Group | Custom EKS cluster SG (`eks-cluster-sg`) |

IAM Role:
- `eksClusterRole` with:
  - `AmazonEKSClusterPolicy`
  - `AmazonEKSServicePolicy`

---

## 7. Node Group

| Key | Value |
|-----|-------|
| Node Group Name | `ng` |
| Instance Type | `t3.medium` |
| Subnets | All private subnets |
| Disk Size | `20 GB` |
| Desired Capacity | `3` |
| Min Capacity | `1` |
| Max Capacity | `4` |

IAM Role:
- `eksNodeGroupRole` with:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEKS_CNI_Policy`
  - `AmazonEC2ContainerRegistryReadOnly`

---

## 8. Cluster Access

- Admin user: `eks-admin-user`
- Access granted via `kubectl patch` on `aws-auth` ConfigMap
- Mapped to `system:masters` group for full cluster admin

---

## 9. Cluster Autoscaler (IRSA)

| Component | Value |
|----------|-------|
| OIDC Provider | Derived from cluster identity |
| IAM Role | `cluster-autoscaler-irsa` |
| IRSA Trust | `system:serviceaccount:kube-system:cluster-autoscaler-aws-cluster-autoscaler` |
| Custom Policy | Grants permissions for AutoScaling and EC2 describe/scale actions |
| Role Attached | Via `aws_iam_role_policy_attachment.cluster_autoscaler_attach` |

---
