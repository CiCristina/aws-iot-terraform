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

# Busca o Account ID automaticamente
data "aws_caller_identity" "current" {}

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
          "arn:aws:iot:us-east-1:${data.aws_caller_identity.current.account_id}:topic/sensor_home/temperatura",
          "arn:aws:iot:us-east-1:${data.aws_caller_identity.current.account_id}:topic/$aws/things/sensor1/shadow/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Subscribe"
        ]
        Resource = [
          "arn:aws:iot:us-east-1:${data.aws_caller_identity.current.account_id}:topicfilter/sensor_home/temperatura",
          "arn:aws:iot:us-east-1:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/things/sensor1/shadow/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "iot:Connect"
        ],
        Resource = [
          "arn:aws:iot:us-east-1:${data.aws_caller_identity.current.account_id}:client/sensor1"
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

# Regra IoT chamando o lambda diretamente
resource "aws_iot_topic_rule" "regra_lambda" {
  name        = "MandarParaLambda"
  description = "Manda dados dos sensores direto para Lambda"
  enabled     = true
  sql         = "SELECT * FROM 'sensor_home/temperatura'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.processador_dados.arn
  }
}

#Criando permissao Role do IoT pra invocar Lambda
resource "aws_iam_role" "iot_role" {
  name = "IoT-Lambda-Role"

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

# Permissão pra IoT invocar Lambda
resource "aws_iam_role_policy" "iot_lambda_policy" {
  name = "IoT-Lambda-Policy"
  role = aws_iam_role.iot_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = aws_lambda_function.processador_dados.arn
      }
    ]
  })
}

# Permissão pro IoT Core invocar a Lambda alem do Role. O IoT Core precisa de permissão
# explícita pra chamar a função Lambda
resource "aws_lambda_permission" "iot_invoke_lambda" {
  statement_id  = "AllowIoTInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processador_dados.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.regra_lambda.arn
}

# Lambda function
resource "aws_lambda_function" "processador_dados" {
  filename         = "../lambda-functions/processador-dados.zip"
  function_name    = "processador-dados-iot"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  timeout          = 60

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

# VPC — igual antes
resource "aws_vpc" "iot_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "IoT VPC"
  }
}

# Subnets
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

# Route Table — Define pra onde vai o tráfego que sai da VPC
resource "aws_route_table" "iot_rt" {
  vpc_id = aws_vpc.iot_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.iot_igw.id
  }

  tags = {
    Name = "IoT Route Table"
  }
}

resource "aws_route_table_association" "rta_subnet_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.iot_rt.id
}

resource "aws_route_table_association" "rta_subnet_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.iot_rt.id
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

# Subnet group para RDS (obrigatório)
resource "aws_db_subnet_group" "iot_subnet_group" {
  name       = "iot-subnet-group"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
  
  tags = {
    Name = "IoT DB subnet group"
  }
}

# RDS
resource "aws_rds_cluster" "iot_database" {
  cluster_identifier     = "iot-database"
  engine                 = "aurora-mysql"
  engine_mode            = "provisioned"
  engine_version         = "8.0.mysql_aurora.3.04.0"
  
  database_name          = "iotdata"
  master_username        = "admin"
  master_password        = var.db_master_password
  
  db_subnet_group_name   = aws_db_subnet_group.iot_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  skip_final_snapshot    = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1.0
  }

  tags = {
    Name = "IoT Database"
  }
}

 # Instância do cluster usando Serverless v2
resource "aws_rds_cluster_instance" "cluster_instances" {
  identifier         = "iot-database-instance-1"
  cluster_identifier = aws_rds_cluster.iot_database.id
  engine             = aws_rds_cluster.iot_database.engine
  engine_version     = aws_rds_cluster.iot_database.engine_version
  instance_class     = "db.serverless"
}

# Outputs
output "database_endpoint" {
  value = aws_rds_cluster.iot_database.endpoint
}