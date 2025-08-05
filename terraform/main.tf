terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Criar uma "coisa" IoT
resource "aws_iot_thing" "sensor_home" {
  name = "sensor1"
  
  attributes = {
    tipo = "temp_sensor"
    localizacao = "bedroom"
  }
}
# Certificado para o dispositivo
resource "aws_iot_certificate" "cert_sensor" {
  active = true
}

# Policy que define o que o dispositivo pode fazer
resource "aws_iot_policy" "policy_sensor" {
  name = "MySimulatedSensorPolicy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Publish",
          "iot:Receive"
        ]
        Resource = [
          "arn:aws:iot:us-east-1:<945189317719>:topic/sensor_home/temperatura",
          "arn:aws:iot:us-east-1:<945189317719>:topic/$aws/things/sensor1/shadow/*" # Se usar shadows
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Subscribe"
        ]
        Resource = [
          "arn:aws:iot:us-east-1:<945189317719>:topicfilter/sensor_home/temperatura",
          "arn:aws:iot:us-east-1:<945189317719>:topicfilter/$aws/things/sensor1/shadow/*" # Se usar shadows
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "iot:Connect"
        ],
        Resource = [
          "arn:aws:iot:us-east-1:<945189317719>:client/sensor1"
        ]
       }
    ]
  })
}

# Conectar policy ao certificado
resource "aws_iot_policy_attachment" "policy_cert" {
  policy = aws_iot_policy.policy_sensor.name
  target = aws_iot_certificate.cert_sensor.arn
}

# Conectar certificado ao dispositivo
resource "aws_iot_thing_principal_attachment" "cert_thing" {
  thing     = aws_iot_thing.sensor_home.name
  principal = aws_iot_certificate.cert_sensor.arn
}
# Stream para receber dados dos sensores
resource "aws_kinesis_stream" "stream_sensores" {
  name             = "iot-dados-sensores"
  shard_count      = 1
  retention_period = 24
  
  tags = {
    Projeto = "IoT-Migration"
  }
}
# Regra que manda dados do IoT para o Kinesis
resource "aws_iot_topic_rule" "regra_kinesis" {
  name        = "MandarParaKinesis"
  description = "Manda dados dos sensores para Kinesis"
  enabled     = true
  sql         = "SELECT * FROM 'topic/sensor/data'"
  sql_version = "2016-03-23"

  kinesis {
    stream_name = aws_kinesis_stream.stream_sensores.name
    role_arn    = aws_iam_role.iot_role.arn
  }
}

# Role para IoT acessar Kinesis
resource "aws_iam_role" "iot_role" {
  name = "IoT-Kinesis-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })
}

# Permissão para escrever no Kinesis
resource "aws_iam_role_policy" "iot_kinesis_policy" {
  name = "IoT-Kinesis-Policy"
  role = aws_iam_role.iot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = aws_kinesis_stream.stream_sensores.arn
      }
    ]
  })
}
# Lambda function
resource "aws_lambda_function" "processador_dados" {
  filename         = "../lambda-functions/processador-dados.zip"
  function_name    = "processador-dados-iot"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 60

  source_code_hash = filebase64sha256("../lambda-functions/processador-dados.zip")
}

# Role para Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-iot-role"

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

# Permissões básicas para Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permissão para ler do Kinesis
resource "aws_iam_role_policy" "lambda_kinesis" {
  name = "lambda-kinesis-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.stream_sensores.arn
      }
    ]
  })
}

# Trigger: Kinesis → Lambda
resource "aws_lambda_event_source_mapping" "kinesis_lambda" {
  event_source_arn  = aws_kinesis_stream.stream_sensores.arn
  function_name     = aws_lambda_function.processador_dados.arn
  starting_position = "LATEST"
}
