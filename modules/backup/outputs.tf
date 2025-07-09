output "backup_bucket_name" {
  value = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  value = aws_s3_bucket.backup.arn
}

output "backup_state_bucket_name" {
  value = aws_s3_bucket.backup_state.id
}

output "backup_state_bucket_arn" {
  value = aws_s3_bucket.backup_state.arn
}