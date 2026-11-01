# The HTTP surface. contracts/api.openapi.yaml.
#
# THE SECURITY BOUNDARY (FR-062, contracts/sync-protocol.md I5).
#
# The Cognito authorizer declared in the OpenAPI document validates signature,
# issuer, audience and expiry before the request reaches any code of ours. A handler
# therefore never sees an unverified claim, and `deriveAccountId` builds the
# partition key from that verified `sub` and nothing else. Every operation inherits
# the top-level `security` block; only /v1/reference-data opts out, with `security:
# []` and a comment saying why.

module "saka_apigateway" {
  source = "../../terraform/modules/apigateway"

  api_gateway_name                         = "${local.name}-api"
  api_gateway_body                         = local.api_gateway_body
  api_gateway_endpoint_configuration_types = ["REGIONAL"]
  api_gateway_stage_name                   = "v1"
  api_gateway_log_group_retention_in_days  = var.log_retention_in_days

  lambda_function_names = [for fn in module.lambda : fn.lambda_function_name]
}
