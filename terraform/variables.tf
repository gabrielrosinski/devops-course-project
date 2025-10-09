variable "aws_region" {
    type    = string
    default = "us-east-1"
}

variable "instance_type" {
    type    = string
    default = "t2.micro"
}

variable "key_name" {
    type    = string
    description = "SSH key pair name"
}