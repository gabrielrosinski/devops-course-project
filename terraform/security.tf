# Security Group - Allow SSH and HTTP
resource "aws_security_group" "web_sg" {
    name        = "earthquake-web-sg"
    description = "Allow SSH, HTTP, Docker, Flask"

    # SSH access
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["46.117.112.88/32"]
    }

    # Flask app
    ingress {
        from_port   = 5000
        to_port     = 5000
        protocol    = "tcp"
        cidr_blocks = ["46.117.112.88/32"]
    }

    # Docker port
    ingress {
        from_port   = 8000
        to_port     = 8000
        protocol    = "tcp"
        cidr_blocks = ["46.117.112.88/32"]
    }

    # HTTP access
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["46.117.112.88/32"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}