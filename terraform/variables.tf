variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used to tag/name all resources"
  type        = string
  default     = "travelmemory"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (web server)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (database)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "AZ for both subnets (keep same AZ for simplicity)"
  type        = string
  default     = "ap-south-1a"
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro avoids the t2.micro pod/instance density issues you hit before)"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of an EXISTING EC2 key pair in your AWS account, used for SSH"
  type        = string
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 49.36.XX.XX/32 (get it from `curl ifconfig.me`)"
  type        = string
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID for ap-south-1. Leave default or override for your region."
  type        = string
  default     = "ami-0f58b397bc5c1f2e8" # Ubuntu 22.04 LTS, ap-south-1 - verify/update before apply
}
