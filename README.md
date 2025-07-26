# Redis Visitor Counter

## Run Locally (Docker)

# Start Redis
docker run -d --name redis redis:7-alpine

# Build app
docker build -t visitor-app .

# Run app (with --link)
docker run -d --name visitor-app --link redis:redis -p 3000:3000 visitor-app

# Or use Docker network
docker network create visitor-net
docker run -d --name redis --network visitor-net redis:7-alpine
docker run -d --name visitor-app --network visitor-net -p 3000:3000 visitor-app

# Visit in browser
http://localhost:3000

## Push to Docker Hub

docker login -u <username>
docker tag visitor-app <username>/visitor-app:latest
docker push <username>/visitor-app:latest

## Infra (EKS)

terraform init
terraform apply
terraform output eks_admin_user_access_key_id
terraform output eks_admin_user_secret_access_key

aws eks update-kubeconfig --name my-eks-cluster --region ap-southeast-1
kubectl get nodes

## Deploy App on EKS
```
kubectl apply -f deployment.yaml
kubectl get svc | grep visitor-app
```
Or
```
helm upgrade --install visitor-app ./chart \
  --namespace dev \
  --create-namespace \
  -f ./chart/values.yaml

```
# Outputs:

cluster_endpoint = "https://<>.ap-southeast-1.eks.amazonaws.com"
eks_admin_user_access_key_id = "<>"
eks_admin_user_arn = "arn:aws:iam::129641968426:user/eks-admin-user"
eks_admin_user_secret_access_key = <sensitive>
vpc_id = "vpc-<>"


# Scaling

# Metrics server for HPA to decide when to scale pods
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 

# Cluster autoscaler to decide when to scale nodes using helm
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=my-eks-cluster \
  --set awsRegion=ap-southeast-1 \
  --set rbac.create=true \
  --set serviceAccount.create=false \
  --set serviceAccount.name=cluster-autoscaler-aws-cluster-autoscaler \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::129641968426:role/cluster-autoscaler-irsa" \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set extraArgs.expander=least-waste \
  --set extraArgs.logtostderr=true \
  --set extraArgs.stderrthreshold=info





