variable "region" {
  description = "The AWS region where the API is deployed."
  default     = "eu-west-2"
}

provider "aws" {
  region = var.region // note backend would usually be backed by S3 bucket for state
}

resource "aws_dynamodb_table" "commitments_table" {
  name           = "CommitmentsTable"
  billing_mode   = "PROVISIONED"
  read_capacity  = 4 // 2 eventually 1 fully consistent reads per second - assuming ~4 requests per second as people subscribe at end of month for a few days. Reading all previous on 'view/add' page. could be up to 8kb (500b record)
  write_capacity = 2 // 1 write per second - assuming ~4 requests per second as people subscribe at end of month for a few days. Adding a new commitment. probably 1kb (500b record)
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_api_gateway_rest_api" "commitments_api" {
  name = "CommitmentsAPI"
}

resource "aws_api_gateway_resource" "commitments_resource" {
  rest_api_id = aws_api_gateway_rest_api.commitments_api.id
  parent_id   = aws_api_gateway_rest_api.commitments_api.root_resource_id
  path_part   = "commitments"
}

resource "aws_api_gateway_method" "commitments_method" {
  rest_api_id   = aws_api_gateway_rest_api.commitments_api.id
  resource_id   = aws_api_gateway_resource.commitments_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.commitments_api.id
  resource_id = aws_api_gateway_resource.commitments_resource.id
  http_method = aws_api_gateway_method.commitments_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_commitment_function.invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.commitments_api.id

  # Specifies the stage name, this will appear in your API's URL
  stage_name = "prod"

  # Depending on your update strategy, you may want to redeploy automatically 
  # when changes are made to the API configuration:
  triggers = {
    redeployment = sha1(join(",", tolist([
      jsonencode(aws_api_gateway_rest_api.commitments_api.body),
      jsonencode(aws_api_gateway_method.commitments_method.http_method),
    ])))
  }

  # Make sure that deployment only happens after all relevant changes
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
  ]

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_commitment_function.function_name
  principal     = "apigateway.amazonaws.com"

  // Adjusted source_arn to align specifically with your API Gateway setup
  source_arn = "${aws_api_gateway_rest_api.commitments_api.execution_arn}/*/*/*"
}

resource "aws_s3_bucket" "functions_bucket" {
  bucket = "ifuller1-bits-functions-bucket"
}

resource "aws_lambda_function" "add_commitment_function" {
  function_name = "AddCommitmentFunction"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  role          = aws_iam_role.lambda_exec.arn

  s3_bucket = aws_s3_bucket.functions_bucket.bucket
  s3_key    = "lambda.zip"

  source_code_hash = filemd5("${path.module}/add-commitment-function/dist/lambda.zip") // naive implementation. better over lockfile and all src
}
# Data source for creating an IAM policy document
data "aws_iam_policy_document" "dynamodb_policy_doc" {
  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.commitments_table.arn]
    effect    = "Allow"
  }
}

# Creating an IAM policy based on the policy document
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name   = "LambdaDynamoDBPolicy"
  policy = data.aws_iam_policy_document.dynamodb_policy_doc.json
}

# Attach the IAM policy to the lambda_execution_role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.functions_bucket.bucket
  key    = "lambda.zip"
  source = "${path.module}/add-commitment-function/dist/lambda.zip"

  etag = filemd5("${path.module}/add-commitment-function/dist/lambda.zip") // naive implementation. better over lockfile and all src
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

output "lambda_function_name" {
  value = aws_lambda_function.add_commitment_function.function_name
}

output "api_gateway_endpoint_url" {
  value       = "https://${aws_api_gateway_rest_api.commitments_api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_deployment.api_deployment.stage_name}/${aws_api_gateway_resource.commitments_resource.path_part}"
  description = "The URL endpoint for the deployed API Gateway."
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.commitments_api.id
  description = "The ID of the API Gateway"
}
