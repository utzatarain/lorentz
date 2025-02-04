resource "aws_ecs_cluster" "portfolio" {
  name = var.name
}

locals {
  api_container = "${var.prefix}-api-run"
  web_container = "${var.prefix}-web-run"
}

data "template_file" "task-definition-template" {
  template = file("${path.module}/task-definition.json.tpl")
  vars = {
    CONTAINER = local.api_container
    IMAGE     = replace(var.hub.repository_url, "https://", "")
    TAG       = "latest"
    PORT      = 3000
  }
}

resource "aws_ecs_task_definition" "api-run" {
  family                   = local.api_container # Naming our first task
  container_definitions    = data.template_file.task-definition-template.rendered
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = aws_iam_role.task-runner.arn
  task_role_arn            = aws_iam_role.task-command-executor.arn
}

resource "aws_iam_role" "task-runner" {
  name               = "${var.prefix}-task-runner"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "task-runner-policy" {
  role       = aws_iam_role.task-runner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task-command-executor" {
  name               = "${var.prefix}-task-command-executor"
  assume_role_policy = data.aws_iam_policy_document.command-executor.json
}

data "aws_iam_policy_document" "command-executor" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "task-command-executor-policy" {
  role       = aws_iam_role.task-command-executor.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_ecs_service" "api" {
  name    = "${var.prefix}-api"
  cluster = aws_ecs_cluster.portfolio.id

  # Referencing the task our service will spin up
  task_definition        = aws_ecs_task_definition.api-run.arn
  launch_type            = "FARGATE"
  enable_execute_command = true
  desired_count          = 2

  load_balancer {
    target_group_arn = aws_lb_target_group.workers.arn
    container_name   = aws_ecs_task_definition.api-run.family
    container_port   = 3000
  }

  network_configuration {
    assign_public_ip = true
    subnets          = var.subnets

    security_groups = [
      aws_security_group.api-access.id,
    ]
  }
}

resource "aws_security_group" "api-access" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    # Only allowing traffic in from the load balancer security group
    security_groups = [
      aws_security_group.alb-entry-point-access.id,
    ]
  }

  egress {
    from_port   = 0             # Allowing any incoming port
    to_port     = 0             # Allowing any outgoing port
    protocol    = "-1"          # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}
