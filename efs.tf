provider "aws" {
  region   = "ap-south-1"
  profile  = "sahiba"
}

resource "tls_private_key" "key-pair" {
  algorithm = "RSA"
  rsa_bits = "2048"
}

resource "local_file" "private_key" {
  content  = tls_private_key.key-pair.private_key_pem
  filename = "sahibakey.pem"
}

resource "aws_key_pair" "key" {
  depends_on = [ tls_private_key.key-pair ,]
  key_name = "sahibakey"
  public_key = tls_private_key.key-pair.public_key_openssh

}
resource "aws_security_group" "task2-sg" {
  depends_on = [aws_key_pair.key,]
  name        = "task2-sg"
  description = "Allow SSH, HTTP, NFS"
  vpc_id      = "vpc-af534fc7"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task2-sg"
  }
}

resource "aws_instance" "myos1" {
  depends_on = [ aws_key_pair.key, aws_security_group.task2-sg ,]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  subnet_id = "subnet-ed9ea485"
  key_name = aws_key_pair.key.key_name
  security_groups = ["${aws_security_group.task2-sg.id}"]

  connection {
   type = "ssh"
   user = "ec2-user"
   private_key = tls_private_key.key-pair.private_key_pem
   host = aws_instance.myos1.public_ip
}

  provisioner "remote-exec" {
    inline = [
       "sudo yum update -y",
       "sudo yum install httpd php git amazon-efs-utils -y",
       "sudo systemctl restart httpd",
       "sudo systemctl enable httpd",
      ]
}
  tags = {
    Name = "MyOS1"
  }
}

output "availzone" {
  value = aws_instance.myos1.availability_zone
}

resource "aws_efs_file_system" "nfs" {
  creation_token = "nfs"

  tags = {
    Name = "nfs"
  }
  depends_on = [aws_security_group.task2-sg, aws_instance.myos1 ,]
}

resource "aws_efs_mount_target" "target" {
  depends_on = [ aws_efs_file_system.nfs,]
  file_system_id = aws_efs_file_system.nfs.id
  subnet_id      = aws_instance.myos1.subnet_id
  security_groups = [ "${aws_security_group.task2-sg.id}"]
}

output "myip" {
  value = aws_instance.myos1.public_ip
}

resource "null_resource" "nullip" {
  provisioner "local-exec" {
    command = "echo ${aws_instance.myos1.public_ip} > publicip.txt"
  }
}

resource "null_resource" "confweb" {

  connection {
   type = "ssh"
   user = "ec2-user"
   private_key = tls_private_key.key-pair.private_key_pem
   host = aws_instance.myos1.public_ip
}
  provisioner "remote-exec" {
    inline = [
      "sudo echo ${aws_efs_file_system.nfs.id}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
      "sudo mount  ${aws_efs_file_system.nfs.id}:/  /var/www/html",
      "sudo curl https://raw.githubusercontent.com/Sahiba31/Hybrid_Task2/master/index.html > index.html", 
      "sudo cp index.html  /var/www/html/"
     
      ]
   }
   depends_on = [
	aws_instance.myos1,
	aws_efs_file_system.nfs,
	aws_efs_mount_target.target,
   ]
}



resource "aws_s3_bucket" "sahibatera-bucket11" {
  depends_on = [ null_resource.confweb, ]
  bucket = "sahibatera-bucket11"
  acl    = "public-read"
  force_destroy = "true"
  versioning {
      enabled = true
   }
  tags = {
    Name = "sahibatera-bucket11"
  }
}

resource "aws_s3_bucket_object" "s3object" {
  depends_on = [aws_s3_bucket.sahibatera-bucket11 ,]
  bucket = aws_s3_bucket.sahibatera-bucket11.id
  key    = "Friends.jpg"
  source = "C:/Users/HP/Desktop/Friends.jpg"
  acl = "public-read"
  content_type = "image/jpg"
}

locals {
  s3_origin_id = "aws_s3_bucket.sahibatera-bucket11.id"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "this is sahiba"
}

resource "aws_cloudfront_distribution" "sahibacloudfront" {
  origin {
     domain_name = aws_s3_bucket.sahibatera-bucket11.bucket_regional_domain_name
     origin_id = local.s3_origin_id

     custom_origin_config {
        http_port = 80
        https_port = 80
        origin_protocol_policy = "match-viewer"
        origin_ssl_protocols = ["TLSv1", "TLSv1.1" , "TLSv1.2"]
      }
    }
    enabled = true
    is_ipv6_enabled = true
    
    default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
   }
   
    restrictions {
    geo_restriction {
      restriction_type = "none"
    }
   }
   
    tags = {
      Environment = "production"
    }
    viewer_certificate {
    cloudfront_default_certificate = true
   }
   
   depends_on = [
      aws_s3_bucket_object.s3object
   ]
}
output "domain-name" {
  value = aws_cloudfront_distribution.sahibacloudfront.domain_name
}

resource "null_resource" "myimage" {
  depends_on = [
     aws_cloudfront_distribution.sahibacloudfront,
  ]
  connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = tls_private_key.key-pair.private_key_pem
      host     = aws_instance.myos1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<center><img src='http://${aws_cloudfront_distribution.sahibacloudfront.domain_name}/Friends.jpg' </center>\" >> /var/www/html/index.html",
      "EOF"
    ]
  }
}
  
resource "null_resource" "nulllocal3" {
  depends_on = [
      null_resource.myimage,
   ]
  provisioner "local-exec" {
  command = "start chrome ${aws_instance.myos1.public_ip}"
   }
}
