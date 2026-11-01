locals {
  # terraform.workspace drives every resource name, as in mr-billing, so two
  # environments cannot collide even if they share an account.
  name = "${terraform.workspace}-saka"

  google_enabled = (
    var.google_client_id != "" &&
    var.google_client_secret_name != "" &&
    var.cognito_domain_prefix != ""
  )

  # The routing source of truth. Operations, which require auth and which do not,
  # and the Cognito authorizer all live in this document — changing a route means
  # changing the contract rather than hand-editing resources.
  api_gateway_body = templatefile("../src/docs/saka-api.json", {
    api_name             = "${local.name}-api"
    user_pool_arn        = module.cognito.user_pool_arn
    mutations_invoke_arn = module.lambda["mutations"].invoke_arn
    snapshot_invoke_arn  = module.lambda["snapshot"].invoke_arn
    account_invoke_arn   = module.lambda["account"].invoke_arn
    reference_invoke_arn = module.lambda["reference"].invoke_arn
  })
}
