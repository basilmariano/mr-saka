resource "aws_api_gateway_rest_api" "main" {
  name = var.api_gateway_name

  # The OpenAPI document is the single source of truth for routing, including which
  # operations require the authorizer. Changing a route means changing the contract,
  # not hand-editing resources here.
  body   = var.api_gateway_body
  policy = var.api_gateway_policy

  endpoint_configuration {
    types = var.api_gateway_endpoint_configuration_types
  }

  # Anything not in the body is removed, so a route deleted from the contract is
  # actually gone rather than left orphaned and reachable.
  put_rest_api_mode = "overwrite"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  # API Gateway does not redeploy because the body changed; it redeploys when this
  # trigger changes. Without it a contract edit applies cleanly and serves the old
  # routes, which looks like success and is not.
  triggers = {
    redeployment = sha1(var.api_gateway_body)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.api_gateway_name}"
  retention_in_days = var.api_gateway_log_group_retention_in_days
}

resource "aws_api_gateway_stage" "main" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = var.api_gateway_stage_name

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn

    # Deliberately excludes request bodies and the Authorization header. These logs
    # would otherwise accumulate users' records and bearer tokens in a store with
    # weaker controls than the data itself.
    format = jsonencode({
      requestId      = "$context.requestId"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      requestTime    = "$context.requestTime"
      errorMessage   = "$context.error.message"
      authorizerErr  = "$context.authorizer.error"
    })
  }
}

resource "aws_api_gateway_method_settings" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
  }
}

resource "aws_lambda_permission" "invoke" {
  for_each = toset(var.lambda_function_names)

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "apigateway.amazonaws.com"

  # Scoped to this API, so another API in the account cannot invoke these functions.
  source_arn = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
