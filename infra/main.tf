provider "aws" {
  region = var.region
}

# IAM user for EKS admin
resource "aws_iam_user" "eks_admin" {
  name = "eks-admin-user"
}
resource "aws_iam_user_policy_attachment" "eks_admin_attach" {
  user       = aws_iam_user.eks_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
resource "aws_iam_access_key" "eks_admin" {
  user = aws_iam_user.eks_admin.name
}

# VPC
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "eks-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "eks-igw" }
}

# Public subnets (one per AZ)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "eks-public-${count.index}" }
}

# Private subnets (one per AZ)
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "eks-private-${count.index}" }
}

# NAT Gateway and EIP for each AZ (can be simplified to 1 if cost is a concern)
resource "aws_eip" "nat" {
  count = length(var.private_subnet_cidrs)
}
resource "aws_nat_gateway" "this" {
  count         = length(var.private_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags = { Name = "eks-natgw-${count.index}" }
}

# Route tables for public/private
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "eks-public" }
}
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.this.id
  tags = { Name = "eks-private-${count.index}" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route" "private_nat" {
  count                  = length(var.private_subnet_cidrs)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Security group for EKS cluster and nodes
resource "aws_security_group" "eks_cluster" {
  name        = "eks-cluster"
  description = "EKS cluster SG"
  vpc_id      = aws_vpc.this.id
  tags = { Name = "eks-cluster-sg" }
}

# EKS role and policies
resource "aws_iam_role" "eks_cluster" {
  name = "eksClusterRole"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}
data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
	  type        = "Service"
	  identifiers = ["eks.amazonaws.com"]
	}

  }
}
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}


# EKS cluster
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSServicePolicy,
  ]
}

# Node group role/policy
resource "aws_iam_role" "eks_nodes" {
  name = "eksNodeGroupRole"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume.json
}
data "aws_iam_policy_document" "nodes_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# Node group
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  instance_types = [var.instance_type]
  disk_size      = 20

  depends_on = [
    aws_eks_cluster.this,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKS_CNI_Policy
  ]
}

# Patch aws-auth ConfigMap for admin user
resource "null_resource" "aws_auth_patch" {
  provisioner "local-exec" {
    command = <<EOT
set -e
aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.region}
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth.yaml
cat aws-auth.yaml | grep -q ${aws_iam_user.eks_admin.arn} || \
kubectl patch configmap/aws-auth -n kube-system --type merge -p '{
  "data":{
    "mapUsers": "- userarn: ${aws_iam_user.eks_admin.arn}\n  username: eks-admin-user\n  groups:\n    - system:masters\n"
  }
}'
EOT
    interpreter = ["bash", "-c"]
  }
  depends_on = [aws_eks_node_group.this]
}

data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler-aws-cluster-autoscaler"]
    }
  }
}

data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd10df6"] # default for EKS
}

resource "aws_iam_role" "cluster_autoscaler_irsa" {
  name               = "cluster-autoscaler-irsa"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role.json
}


data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name   = "ClusterAutoscalerPolicy"
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler_attach" {
  role       = aws_iam_role.cluster_autoscaler_irsa.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}
