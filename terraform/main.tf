module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = "tf-vpc"
  cidr = "10.0.0.0/16"
  azs = ["eu-west-2a", "eu-west-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway = true
  tags = {
    Terraform = "true"
    Environment = "prod"
    Name = "tf-vpc"
  }
}

resource "aws_security_group" "lb_sg" {
  name   = "lb-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
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

resource "aws_security_group" "ecs_sg" {
  name   = "ecs-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_alb" "app-lb" {
  name               = "app-lb"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.lb_sg.id]
}

resource "aws_lb_target_group" "app-tg" {
  name        = "app-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    matcher = "200"
    path    = "/health"
  }
}

resource "aws_lb_listener" "app-lb-listener" {
  load_balancer_arn = aws_alb.app-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app-tg.arn
  }
}

resource "aws_ecs_task_definition" "app-td" {
  family                   = "app-td"
  container_definitions    = <<EOF
  [
    {
      "name": "app",
      "image": "339712838836.dkr.ecr.eu-west-2.amazonaws.com/trb:${var.image_tag}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  EOF
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole-tf"
  assume_role_policy = data.aws_iam_policy_document.aws_iam_policy_document.json
}

data "aws_iam_policy_document" "aws_iam_policy_document" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_ecs_cluster" "app-ecs" {
  name = "app-cluster"
}

resource "aws_ecs_service" "app-ecs-service" {
  name            = "app-ecs-service"
  cluster         = aws_ecs_cluster.app-ecs.id
  task_definition = aws_ecs_task_definition.app-td.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app-tg.arn
    container_name   = "app"
    container_port   = 80
  }
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
