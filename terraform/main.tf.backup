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

variable "db_master_password" {
  type        = string
  description = "DB Password."
  sensitive   = true
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
# Subnet group para RDS (obrigatório)
resource "aws_db_subnet_group" "iot_subnet_group" {
  name       = "iot-subnet-group"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
  
  tags = {
    Name = "IoT DB subnet group"
  }
}

# VPC (rede virtual)
resource "aws_vpc" "iot_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "IoT VPC"
  }
}

# Subnets (sub-redes)
resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.iot_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1c"
  
  tags = {
    Name = "IoT Subnet A"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.iot_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1d"
  
  tags = {
    Name = "IoT Subnet B"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "iot_igw" {
  vpc_id = aws_vpc.iot_vpc.id
  
  tags = {
    Name = "IoT Internet Gateway"
  }
}

# Security Group para RDS
resource "aws_security_group" "rds_sg" {
  name_prefix = "rds-sg"
  vpc_id      = aws_vpc.iot_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS Aurora Serverless
resource "aws_rds_cluster" "iot_database" {
  cluster_identifier      = "iot-database"
  engine                 = "aurora-mysql"
  
  database_name          = "iotdata"
  master_username        = "admin"
  master_password        = var.db_master_password
  
  db_subnet_group_name   = aws_db_subnet_group.iot_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  skip_final_snapshot = true  # Para testes
  
  
  tags = {
    Name = "IoT Database"
  }
}

# instância do cluster
resource "aws_rds_cluster_instance" "cluster_instances" {
  identifier         = "iot-database-instance-1"
  cluster_identifier = aws_rds_cluster.iot_database.id
  engine             = aws_rds_cluster.iot_database.engine
  instance_class     = "db.t3.medium" # Escolha um tipo de instância
}
# Outputs importantes
output "database_endpoint" {
  value = aws_rds_cluster.iot_database.endpoint
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.stream_sensores.name
}
