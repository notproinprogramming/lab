terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true

  s3_use_path_style = true
  
  endpoints {
    s3     = "http://localhost:4566"
    lambda = "http://localhost:4566"
    iam    = "http://localhost:4566"
    logs   = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "start_bucket" {
  bucket = "my-start-bucket" 
}

resource "aws_s3_bucket" "finish_bucket" {
  bucket = "my-finish-bucket"
}

resource "aws_s3_bucket_lifecycle_configuration" "start_bucket_lifecycle" {
  bucket = aws_s3_bucket.start_bucket.id

  rule {
    id     = "move-to-glacier"
    status = "Enabled"

    filter {
      prefix = "" 
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda_s3_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:Get*", 
          "s3:Head*", 
          "s3:List*",
          "s3:Head*",
          "s3:HeadBucket",
          "s3:HeadObject",
          "s3:CopyObject"
        ]
        Resource = [
          "${aws_s3_bucket.start_bucket.arn}/*",
          "${aws_s3_bucket.finish_bucket.arn}/*",
          aws_s3_bucket.start_bucket.arn,
          aws_s3_bucket.finish_bucket.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_logs_policy" {
  name = "lambda_logs_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      Resource = ["arn:aws:logs:*:*:*"]
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/s3_copy_function"  
  retention_in_days = 7
}

resource "null_resource" "package_lambda" {
  triggers = {
    always_run = timestamp()
  }
  
  provisioner "local-exec" {
    command = "zip -r lambda_function.zip lambda_function.py"
  }
}

resource "aws_lambda_function" "s3_copy_lambda" {
  filename      = "lambda_function.zip"
  function_name = "s3_copy_function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.8"
  timeout       = 30

  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      DESTINATION_BUCKET = aws_s3_bucket.finish_bucket.id
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_s3_policy,
    aws_iam_role_policy.lambda_logs_policy,
    null_resource.package_lambda
  ]
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_copy_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.start_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.start_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_copy_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}
