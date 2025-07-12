output "scripts_bucket_name" {
  value = aws_s3_bucket.scripts.id
}

output "scripts_bucket_arn" {
  value = aws_s3_bucket.scripts.arn
}

output "scripts_version" {
  value = var.scripts_version
}