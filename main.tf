# ----------------------
# VARIABLES & PROVIDER
# ----------------------
provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-west-2"
}

variable "project_name" {
  default = "voice-sentiment-ai"
}

# ----------------------
# S3 BUCKET FOR AUDIO FILES
# ----------------------
resource "aws_s3_bucket" "audio_input" {
  bucket = "${var.project_name}-audio-input"
  force_destroy = true
}

# ----------------------
# IAM ROLES & POLICIES
# ----------------------
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_custom_policy" {
  name = "${var.project_name}-lambda-custom-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "transcribe:*",
          "comprehend:*",
          "translate:*",
          "dynamodb:PutItem"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_custom_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_custom_policy.arn
}

# ----------------------
# LAMBDA FUNCTION
# ----------------------
resource "aws_lambda_function" "process_audio" {
  function_name = "${var.project_name}-process-audio"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "./lambda_function_payload.zip"
  source_code_hash = filebase64sha256("./lambda_function.zip")
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.analysis_results.name
    }
  }
}

# ----------------------
# S3 EVENT TRIGGER
# ----------------------
resource "aws_s3_bucket_notification" "trigger_lambda" {
  bucket = aws_s3_bucket.audio_input.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.process_audio.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_audio.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.audio_input.arn
}

# ----------------------
# DYNAMODB FOR RESULTS
# ----------------------
resource "aws_dynamodb_table" "analysis_results" {
  name         = "${var.project_name}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# ----------------------
# OUTPUTS
# ----------------------
output "s3_bucket_name" {
  value = aws_s3_bucket.audio_input.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.process_audio.function_name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.analysis_results.name
}
