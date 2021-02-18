data "aws_subnet_ids" "public-subnet" {
  vpc_id = var.vpc_id
}

data "aws_subnet_ids" "private-subnet" {
  vpc_id = var.vpc_id
}

//creating autoscalinggroup

resource "aws_autoscaling_group" "asg" {
  name                      = var.asg_name
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 3
  force_delete              = true
  launch_configuration      = aws_launch_configuration.lc.name
  vpc_zone_identifier       = data.aws_subnet_ids.private-subnet.ids

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "agents-scale-up" {
    name = "agents-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.asg.name}"
}

resource "aws_autoscaling_policy" "agents-scale-down" {
    name = "agents-scale-down"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.asg.name}"
}

//Creating Launch-config
resource "aws_launch_configuration" "lc" {
  name_prefix   = "poc-lc-"
  image_id      = var.ami
  instance_type = var.instance_type
  security_groups = [aws_security_group.ec2-security.id]
  user_data       = file("data.sh")

}

// creating LoadBalancer

resource "aws_lb" "lb" {
  name               = var.lb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls.id]
  subnets            = data.aws_subnet_ids.public-subnet.ids
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "test" {
  name     = var.tg_name
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}

resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }

  condition {
    host_header {
      values = [var.hostname]
    }
  }

}

//EC2-security_group

resource "aws_security_group" "ec2-security" {
  name        = "server-sg"
  vpc_id      = var.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.allow_tls.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_tls" {
  name        = var.security_group_name
  description = "Allow TLS inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.asg.id
  alb_target_group_arn   = aws_lb_target_group.test.arn
}

resource "aws_cloudwatch_metric_alarm" "cpu-high" {
  alarm_name                = "demo-cpu-high"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "120"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  alarm_actions = [
        "${aws_autoscaling_policy.agents-scale-up.arn}"
    ]
  dimensions = {
      AutoScalingGroupName = "${aws_autoscaling_group.asg.name}"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu-low" {
  alarm_name                = "demo-cpu-low"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "120"
  statistic                 = "Average"
  threshold                 = "40"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  alarm_actions = [
        "${aws_autoscaling_policy.agents-scale-down.arn}"
    ]
  dimensions = {
      AutoScalingGroupName = "${aws_autoscaling_group.asg.name}"
  }
}

// CW aws_cloudwatch_metric_alarm

resource "aws_cloudwatch_metric_alarm" "req_error_alarm" {
  alarm_name                = "req-error-rate-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "2"
  threshold                 = "10"
  alarm_description         = "Request error rate has exceeded 10%"
  insufficient_data_actions = []

  metric_query {
    id          = "e1"
    expression  = "m2/m1*100"
    label       = "Error Rate"
    return_data = "true"
  }

  metric_query {
    id = "m1"

    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = "120"
      stat        = "Sum"
      unit        = "Count"

      dimensions = {
          LoadBalancer = "${ aws_lb.lb.name}"
      }
    }
  }

  metric_query {
    id = "m2"

    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = "120"
      stat        = "Sum"
      unit        = "Count"

      dimensions = {
          LoadBalancer = "${ aws_lb.lb.name}"
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_anomaly_detection" {
  alarm_name                = "cpu-anomaly-alarm"
  comparison_operator       = "GreaterThanUpperThreshold"
  evaluation_periods        = "2"
  threshold_metric_id       = "e1"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1)"
    label       = "CPUUtilization (Expected)"
    return_data = "true"
  }

  metric_query {
    id          = "m1"
    return_data = "true"
    metric {
      metric_name = "CPUUtilization"
      namespace   = "AWS/EC2"
      period      = "120"
      stat        = "Average"
      unit        = "Count"

      dimensions = {
          AutoScalingGroupName = "${aws_autoscaling_group.asg.name}"
      }
    }
  }
}

output "lb_dns" {
  value = "${aws_lb.lb.dns_name}"
}
