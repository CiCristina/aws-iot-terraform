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
