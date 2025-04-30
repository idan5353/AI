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

resource "aws_s3_bucket_ownership_controls" "audio_input" {
  bucket = aws_s3_bucket.audio_input.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "audio_input" {
  depends_on = [aws_s3_bucket_ownership_controls.audio_input]
  bucket = aws_s3_bucket.audio_input.id
  acl    = "private"
}

# ----------------------
# S3 BUCKET CORS CONFIG
# ----------------------
resource "aws_s3_bucket_cors_configuration" "audio_input" {
  bucket = aws_s3_bucket.audio_input.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
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
        Effect    = "Allow",
        Action    = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "transcribe:StartTranscriptionJob",
          "transcribe:GetTranscriptionJob",
          "comprehend:DetectSentiment",
          "comprehend:DetectDominantLanguage",
          "translate:TranslateText",
          "dynamodb:PutItem"
        ],
        Resource  = "*"
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
  filename      = "./lambda_function.zip"
  source_code_hash = filebase64sha256("./lambda_function.zip")
  timeout       = 300  # 5 minutes
  memory_size   = 256  # MB
  
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
    filter_prefix       = "uploads/"  # אופצינלי - מופעל רק על קבצים בתיקייה הזו
    filter_suffix       = ".mp3,.wav,.ogg,.flac,.mp4,.m4a,.webm"  # אופצינלי - מופעל רק על קבצים עם הסיומות הללו
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
# POLICY FOR TRANSCRIBE SERVICE
# ----------------------
resource "aws_iam_role" "transcribe_service_role" {
  name = "${var.project_name}-transcribe-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "transcribe.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "transcribe_s3_access" {
  name = "${var.project_name}-transcribe-s3-access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = [
          "${aws_s3_bucket.audio_input.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "transcribe_s3_access_attach" {
  role       = aws_iam_role.transcribe_service_role.name
  policy_arn = aws_iam_policy.transcribe_s3_access.arn
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
