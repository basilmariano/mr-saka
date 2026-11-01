output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.main.function_name
}

output "arn" {
  description = "The ARN of the lambda function"
  value       = aws_lambda_function.main.arn
}

output "invoke_arn" {
  description = "The invoke ARN of the lambda function"
  value       = aws_lambda_function.main.invoke_arn
}

output "iam_name" {
  description = "The name of the IAM role assigned to the lambda function"
  value       = aws_iam_role.iam_for_lambda.name
}
