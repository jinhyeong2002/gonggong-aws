resource "aws_db_instance" "postgres" {
  identifier = "${local.name_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username

  manage_master_user_password = true

  allocated_storage       = var.db_allocated_storage
  storage_type            = "gp3"
  backup_retention_period = var.db_backup_retention_period

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  deletion_protection = !var.skip_final_snapshot
  skip_final_snapshot = var.skip_final_snapshot

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-postgres"
  })
}

