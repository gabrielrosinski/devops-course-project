resource "aws_instance" "web" {
    ami           = "ami-0360c520857e3138f" #Ubuntu Server 24.04 LTS
    instance_type = var.instance_type
    key_name      = var.key_name

    vpc_security_group_ids = [aws_security_group.web_sg.id]

    tags = {
        Name = "earthquake-web"
    }
}