# Voice Sentiment AI Analysis on AWS

This project is a serverless AI-powered pipeline that analyzes audio files uploaded to an S3 bucket. It uses a combination of AWS services to transcribe, translate, and analyze the sentiment of speech from audio recordings.

## 🔧 Architecture

- **Amazon S3**: Stores uploaded audio files and transcription results.
- **AWS Lambda**: Processes audio uploads, invokes Amazon Transcribe, Amazon Translate (if needed), and Amazon Comprehend for sentiment analysis.
- **Amazon Transcribe**: Converts audio speech into text.
- **Amazon Translate** *(optional)*: Translates non-English text into English.
- **Amazon Comprehend**: Analyzes text to determine sentiment (Positive, Negative, Neutral, Mixed).
- **Amazon DynamoDB**: Stores analysis results, including sentiment, timestamps, and original audio file reference.
- **IAM Roles & Policies**: Provide secure, least-privilege access to each AWS service.
- **Terraform**: Used to provision all cloud infrastructure as code.

## 🚀 How It Works

1. An audio file is uploaded to the S3 bucket.
2. An S3 event triggers the Lambda function.
3. Lambda starts a transcription job with Amazon Transcribe.
4. Once the transcription is ready, the Lambda:
   - Optionally translates the text.
   - Analyzes sentiment with Comprehend.
   - Saves the results in DynamoDB.

## 📁 Project Files

- `main.tf`: Terraform configuration for S3, Lambda, IAM roles, DynamoDB, etc.
- `lambda_function.zip`: Lambda function package with all logic in Python.
- `README.md`: This file.

## 🧠 Use Cases

- Customer service analysis from voice recordings.
- Real-time or batch processing of call center audio.
- Sentiment-based feedback reporting.

## ✅ Prerequisites

- AWS CLI configured
- Terraform installed
- Python 3.11 for Lambda packaging

## 📦 Deploy

```bash
terraform init
terraform apply
