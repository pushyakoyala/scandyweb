provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAWH42Z2OMWHWNKXX5"
  secret_key = "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"
}

resource "aws_instance" "base" {
  ami                    = "ami-0697c829e70e3582f"
  instance_type          = "t2.medium"
  count                  = 2
  key_name               = "${aws_key_pair.keypair.key_name}"
  vpc_security_group_ids = [aws_security_group.allow_ports.id]
  user_data = <<-EOF
             #!/bin/bash/
             sudo apt-get update && apt upgrade
  EOF
  tags                   = { name = "scandy2${count.index}" }
}
resource "aws_key_pair" "keypair" {
  key_name = "scandy2"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCCi5j7hJtN8uRumaHfwf8R3LewRQBhiv+R4ib+3hJZo7OuCEm2xkR+ychBlwnWxewVqezVYw3KQs0TVYFADJEoXNV6uBACZctd8ore5c2t/iOMnBhqnsMgh3ry3ffGPltwbFT2toBJ3kWg3Pzm3m3XH4UhEtQ3AqZuEFsO/TvQNS4wXS5DoXck8g9x2Hjq1uAtBqm4FisZsJeVrvxzWVVcUJwYFWt6xmpyaLm0Oj/bKGAZiGawjt6OMBeFOlPmr2H2QMSxxXeqai5KMRWiizHZfprrNPMavkbkdm62aP69eCZHbqVsq8YEz6IpZQfE7VaBmKQub18Gam/iJH3mtUIX imported-openssh-key"
}


resource "aws_default_vpc" "default" {
  tags = {
    name = "default vpc"
  }
}

resource "aws_security_group" "allow_ports" {
name = "allow-all-sg"
vpc_id = "${aws_default_vpc.default.id}"
ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
 ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 80
    to_port = 80
    protocol = "tcp"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
}


data "aws_subnet_ids" "subnet" {
  vpc_id = "${aws_default_vpc.default.id}"
}

resource "aws_lb_target_group" "magento1" {
  health_check {
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  name        = "magento1"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = "${aws_default_vpc.default.id}"
}

resource "aws_lb_target_group" "varnish1" {
  health_check {
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }


  name        = "varnish1"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = "${aws_default_vpc.default.id}"
}
resource "aws_lb_target_group_attachment" "my-alb-target-group-attachment1" {
  count = length(aws_instance.base)
  target_group_arn = aws_lb_target_group.magento1.arn
  target_id        = aws_instance.base[count.index].id
  port             = 80
}
resource "aws_lb_target_group_attachment" "my-alb-target-group-attachment2" {
  count = length(aws_instance.base)
  target_group_arn = aws_lb_target_group.magento1.arn
  target_id        = aws_instance.base[count.index].id
  port             = 80
}
resource "aws_lb" "my-aws-alb" {
  name     = "my-test-alb"
  internal = false

  security_groups = [
    "${aws_security_group.allow_ports.id}",
  ]

  subnets = data.aws_subnet_ids.subnet.ids

  tags = {
    Name = "my-test-alb"
  }

  ip_address_type    = "ipv4"
  load_balancer_type = "application"
}

resource "aws_lb_listener" "redirect_http" {
  load_balancer_arn = aws_lb.my-aws-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "tls" {
  load_balancer_arn = aws_lb.my-aws-alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:429284512665:certificate/037a2fc5-5c67-44d3-8f71-47123e148b92"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.varnish1.arn
  }
}




resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.tls.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.magento1.arn
  }

  condition {
    path_pattern {
      values = ["/static/*", "/media/*"]
    }
  }

  condition {
    host_header {
      values = ["mitraloves.xyz"]
    }
  }
}


resource "aws_lb_listener_rule" "media" {
  listener_arn = aws_lb_listener.redirect_http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.magento1.arn
  }

  condition {
    path_pattern {
      values = ["/static/*", "/media/*"]
    }
  }

  condition {
    host_header {
      values = ["mitralovesrash.xyz"]
    }
  }
}
