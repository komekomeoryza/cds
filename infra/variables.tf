variable "region" {
  default = "ap-southeast-1"
}
variable "cluster_name" {
  default = "my-eks-cluster"
}
variable "vpc_cidr" {
  default = "55.0.0.0/16"
}
variable "public_subnet_cidrs" {
  default = ["55.0.1.0/24", "55.0.2.0/24", "55.0.3.0/24"]
}
variable "private_subnet_cidrs" {
  default =  ["55.0.101.0/24", "55.0.102.0/24", "55.0.103.0/24"] 
}
variable "instance_type" {
  default = "t3.medium"
}
variable "desired_size" {
  default = 3
}
variable "max_size" {
  default = 4
}
variable "min_size" {
  default = 1
}
