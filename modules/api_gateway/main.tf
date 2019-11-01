
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}


# create the role that API Gateway can use to call Step Functions.
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "api_gw" {
  statement {
    actions   = ["sqs:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "api_gw" {
  name        = "${var.project_name}-api-gw"
  description = "Policy used by the Ldap Maintenance API Gateway"
  policy      = "${data.aws_iam_policy_document.api_gw.json}"
}

resource "aws_iam_role" "api_gw" {
  name = "${var.project_name}-api-gw"

  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = var.tags
}

resource "aws_iam_policy_attachment" "api_gw" {
  name       = "ldap-maintainer-api-gw"
  roles      = ["${aws_iam_role.api_gw.name}"]
  policy_arn = "${aws_iam_policy.api_gw.arn}"
}

# Create the api
# largely stolen from here:
# https://aws.amazon.com/blogs/compute/implementing-serverless-manual-approval-steps-in-aws-step-functions-and-amazon-api-gateway/
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api"
  description = "API for managing LDAP maintenance tasks"
}

resource "aws_api_gateway_resource" "event_listener" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  path_part   = "event-listener"
}

resource "aws_api_gateway_method" "event_listener_post" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.event_listener.id}"
  http_method   = "POST"
  authorization = "NONE"
}

locals {
  request_template = <<TEMPLATE
Action=SendMessage&MessageBody=
#set($allParams = $input.params())
{
"body-json" : $input.json('$'),
"params" : {
#foreach($type in $allParams.keySet())
    #set($params = $allParams.get($type))
"$type" : {
    #foreach($paramName in $params.keySet())
    "$paramName" : "$util.escapeJavaScript($params.get($paramName))"
        #if($foreach.hasNext),#end
    #end
}
    #if($foreach.hasNext),#end
#end
},
"stage-variables" : {
#foreach($key in $stageVariables.keySet())
"$key" : "$util.escapeJavaScript($stageVariables.get($key))"
    #if($foreach.hasNext),#end
#end
}
}
TEMPLATE

}

resource "aws_api_gateway_integration" "event_listener" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_resource.event_listener.id}"
  http_method = "${aws_api_gateway_method.event_listener_post.http_method}"
  credentials = "${aws_iam_role.api_gw.arn}"
  type        = "AWS"

  integration_http_method = "POST"
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json"                  = local.request_template
    "application/x-www-form-urlencoded" = local.request_template
  }

  uri                  = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${var.slack_event_listener_sqs_queue_name}"
  passthrough_behavior = "WHEN_NO_TEMPLATES"
}

resource "aws_api_gateway_method_response" "event_listener_response_200" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_resource.event_listener.id}"
  http_method = "${aws_api_gateway_method.event_listener_post.http_method}"
  response_models = {
    "application/json"                  = "Empty"
    "application/x-www-form-urlencoded" = "Empty"
  }
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "event_listener_response_200" {
  depends_on = [
    "aws_api_gateway_integration.event_listener"
  ]
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_resource.event_listener.id}"
  http_method = "${aws_api_gateway_method.event_listener_post.http_method}"
  status_code = "${aws_api_gateway_method_response.event_listener_response_200.status_code}"
}

# deploy the api
resource "aws_api_gateway_deployment" "respond" {
  depends_on = [
    "aws_api_gateway_integration.event_listener"
  ]
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "respond"
}
