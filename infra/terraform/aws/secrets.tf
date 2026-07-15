locals {
  app_secret_names = toset([
    "OPENAI_API_KEY",
    "SAFETY_KOREA_API_KEY",
    "CUSTOMS_API_KEY",
    "CHEMICAL_API_KEY",
    "CUSTOMS_CONFIRMATION_SERVICE_KEY"
  ])
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.app_secret_names

  name                    = "${local.name_prefix}/${each.key}"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}/${each.key}"
  })
}

