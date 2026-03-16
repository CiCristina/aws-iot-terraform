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

  #precisamos dizer pra Lambda onde estão os valores do process.env.DB_HOST por ex. Variaveis de ambiente - conectam a Lambda ao RDS
  environment { 
  variables = {
    DB_HOST     = aws_db_instance.iot_database.address
    DB_USER     = "admin"
    DB_PASSWORD = var.db_master_password
    DB_NAME     = "iotdata"
    }
  }

  #Config lambda para rodar dentro da VPC. Aqui estou falando em quais subnets ela vai rodar, ainda falta dar permissao. Adicionar VPC config na Lamba. Aqui temos duas subnets por causa de resiliencia e m relacao as availability zones
  vpc_config {
    subnet_ids         = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
    security_group_ids = [aws_security_group.rds_sg.id]
  }

source_code_hash = filebase64sha256("../lambda-functions/processador-dados.zip") #Para terraform ver se o arquivo ZIP mudou e se tem necessidade de fazer o upload novamente/ pega o arquivo, processa matematicamente e retorna uma string única.
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

# Permissões  na IAM Role para Lambda acessar recursos dentro da VPC (RDS)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
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

# RDS MySQL — free tier (db.t3.micro = 750h/mês grátis)
resource "aws_db_instance" "iot_database" {
  identifier        = "iot-database"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  
  db_name           = "iotdata"
  username          = "admin"
  password          = var.db_master_password
  
  db_subnet_group_name   = aws_db_subnet_group.iot_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  allocated_storage = 20  # GB mínimo
  
  skip_final_snapshot = true
  
  tags = {
    Name = "IoT Database"
  }
}

# Output
output "database_endpoint" {
  value = aws_db_instance.iot_database.endpoint
}

# Lambda buscador de leituras
resource "aws_iam_role" "lambda_reader_role" {
  name = "lambda-reader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_reader_basic" {
  role       = aws_iam_role.lambda_reader_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_reader_vpc" {
  role       = aws_iam_role.lambda_reader_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "buscador_leituras" {
  filename      = "../lambda-functions/buscador-leituras.zip"
  function_name = "buscador-leituras-iot"
  role          = aws_iam_role.lambda_reader_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30

  environment {
    variables = {
      DB_HOST     = aws_db_instance.iot_database.address
      DB_USER     = "admin"
      DB_PASSWORD = var.db_master_password
      DB_NAME     = "iotdata"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
    security_group_ids = [aws_security_group.rds_sg.id]
  }

  source_code_hash = filebase64sha256("../lambda-functions/buscador-leituras.zip")
}

# API Gateway
resource "aws_api_gateway_rest_api" "iot_api" {
  name        = "iot-sensor-api"
  description = "API para consultar leituras dos sensores"
}

resource "aws_api_gateway_resource" "leituras" {
  rest_api_id = aws_api_gateway_rest_api.iot_api.id
  parent_id   = aws_api_gateway_rest_api.iot_api.root_resource_id
  path_part   = "leituras"
}

resource "aws_api_gateway_resource" "leituras_ultima" {
  rest_api_id = aws_api_gateway_rest_api.iot_api.id
  parent_id   = aws_api_gateway_resource.leituras.id
  path_part   = "ultima"
}

#métodos GET para os recursos da API e integração com a Lambda buscadora de leituras
resource "aws_api_gateway_method" "get_leituras" {
  rest_api_id   = aws_api_gateway_rest_api.iot_api.id
  resource_id   = aws_api_gateway_resource.leituras.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_leituras_ultima" {
  rest_api_id   = aws_api_gateway_rest_api.iot_api.id
  resource_id   = aws_api_gateway_resource.leituras_ultima.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration_leituras" {
  rest_api_id             = aws_api_gateway_rest_api.iot_api.id
  resource_id             = aws_api_gateway_resource.leituras.id
  http_method             = aws_api_gateway_method.get_leituras.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.buscador_leituras.invoke_arn
}

resource "aws_api_gateway_integration" "integration_leituras_ultima" {
  rest_api_id             = aws_api_gateway_rest_api.iot_api.id
  resource_id             = aws_api_gateway_resource.leituras_ultima.id
  http_method             = aws_api_gateway_method.get_leituras_ultima.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.buscador_leituras.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.buscador_leituras.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.iot_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "iot_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.iot_api.id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_integration.integration_leituras,
    aws_api_gateway_integration.integration_leituras_ultima
  ]
}

output "api_url" {
  value = "${aws_api_gateway_deployment.iot_api_deployment.invoke_url}/leituras"
}