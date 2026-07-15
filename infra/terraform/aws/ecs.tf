resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}-api"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-logs"
  })
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.name_prefix}-ecs-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = concat(
          [for secret in aws_secretsmanager_secret.app : secret.arn],
          [aws_db_instance.postgres.master_user_secret[0].secret_arn]
        )
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = local.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        },
        {
          name  = "DB_URL"
          value = "jdbc:postgresql://${aws_db_instance.postgres.address}:5432/${var.db_name}"
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        {
          name  = "OPENAI_MODEL"
          value = var.openai_model
        },
        {
          name  = "OPENAI_EMBEDDING_MODEL"
          value = var.openai_embedding_model
        },
        {
          name  = "SPRING_AI_VECTORSTORE_PGVECTOR_INITIALIZE_SCHEMA"
          value = tostring(var.pgvector_initialize_schema)
        },
        {
          name  = "CUSTOMS_CONFIRMATION_API_URL"
          value = var.customs_confirmation_api_url
        },
        {
          name  = "SPRING_JPA_HIBERNATE_DDL_AUTO"
          value = var.spring_jpa_hibernate_ddl_auto
        },
        {
          name  = "HSK_EMBEDDING_INITIALIZE"
          value = tostring(var.hsk_embedding_initialize)
        },
        {
          name  = "HSK_DATASET_INITIALIZE"
          value = tostring(var.hsk_dataset_initialize)
        },
        {
          name  = "TARIFF_DATASET_INITIALIZE"
          value = tostring(var.tariff_dataset_initialize)
        }
      ]

      secrets = concat(
        [
          {
            name      = "DB_PASSWORD"
            valueFrom = "${aws_db_instance.postgres.master_user_secret[0].secret_arn}:password::"
          }
        ],
        [
          for name, secret in aws_secretsmanager_secret.app : {
            name      = name
            valueFrom = secret.arn
          }
        ]
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api"
  })
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = var.ecs_health_check_grace_period_seconds

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = local.app_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = local.ecs_assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener.https,
    aws_iam_role_policy_attachment.ecs_task_execution
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api"
  })
}
