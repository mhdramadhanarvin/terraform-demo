# Configure the AWS provider
provider "aws" {
  region = "ap-southeast-1"
}

# Data source: query the list of availability zones
data "aws_availability_zones" "all" {
  state = "available"
} 

# Create a Security Group for an EC2 instance
resource "aws_security_group" "instance" {
  name = "terraform-sg-instance"
  
  ingress {
    from_port	  = "${var.server_port}"
    to_port		  = "${var.server_port}"
    protocol	  = "tcp"
    cidr_blocks	= ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create a Security Group for an ELB
resource "aws_security_group" "elb" {
  name = "terraform-sg-elb"
  
  ingress {
    from_port	  = 80
	  to_port		  = 80
	  protocol	  = "tcp"
	  cidr_blocks	= ["0.0.0.0/0"]
  }

  egress {
    from_port	  = 0
	  to_port		  = 0
	  protocol	  = "-1"
	  cidr_blocks	= ["0.0.0.0/0"]
  }
}

# Create a Launch Configuration
resource "aws_launch_configuration" "example" {
  image_id		    = "ami-0d058fe428540cd89"
  instance_type   = "t2.micro"
  security_groups = ["${aws_security_group.instance.id}"]
  
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, Madhann" > index.html
              nohup busybox httpd -f -p "${var.server_port}" &
              EOF
			  
  lifecycle {
    create_before_destroy = true
  }
}

# Create an Autoscaling Group
resource "aws_autoscaling_group" "example" {
  launch_configuration = "${aws_launch_configuration.example.id}"
  availability_zones   = ["${data.aws_availability_zones.all.names[0]}"]
  
  load_balancers       = ["${aws_elb.example.name}"]
  health_check_type    = "ELB"
  
  min_size             = 2
  max_size             = 10
  desired_capacity     = 2
  
  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "asg_policy_scale_up" 
  autoscaling_group_name = aws_autoscaling_group.example.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 2
  cooldown               = 120 
}

resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_description   = "Monitors CPU utilization for Terramino ASG"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  alarm_name          = "alarm_cpu_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "30"
  evaluation_periods  = "2"
  period              = "120"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "asg_policy_scale_down" 
  autoscaling_group_name = aws_autoscaling_group.example.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 120 
}

resource "aws_cloudwatch_metric_alarm" "scale_down" {
  alarm_description   = "Monitors CPU utilization for Terramino ASG"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  alarm_name          = "alarm_cpu_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "30"
  evaluation_periods  = "2"
  period              = "120"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }
} 

# Create an ELB
resource "aws_elb" "example" {
  name               = "terraform-elb-example"
  availability_zones = ["${data.aws_availability_zones.all.names[0]}"]
  security_groups    = ["${aws_security_group.elb.id}"]
  
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = "${var.server_port}"
    instance_protocol = "http"
  }
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:${var.server_port}/"
  }
}