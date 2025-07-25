output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}
output "vpc_id" {
  value = aws_vpc.this.id
}
output "eks_admin_user_access_key_id" {
  value = aws_iam_access_key.eks_admin.id
}
output "eks_admin_user_secret_access_key" {
  value     = aws_iam_access_key.eks_admin.secret
  sensitive = true
}
output "eks_admin_user_arn" {
  value = aws_iam_user.eks_admin.arn
}
