import time
import json
import random
from datetime import datetime
from awscrt import mqtt
from awsiot import mqtt_connection_builder

# Conf endpoint IoT Core
ENDPOINT = "a3tjjcq85lgeu4-ats.iot.us-east-1.amazonaws.com"
CLIENT_ID = "sensor1"
TOPIC = "sensor_home/temperatura"

# Caminhos dos certificados
CERT_PATH = "scripts/certs/certificate.pem"
KEY_PATH = "scripts/certs/private.key"
CA_PATH = "scripts/certs/AmazonRootCA1.pem"

def conectar():
    print("Conectando ao IoT Core...")
    
    conexao = mqtt_connection_builder.mtls_from_path(
        endpoint=ENDPOINT,
        cert_filepath=CERT_PATH,
        pri_key_filepath=KEY_PATH,
        ca_filepath=CA_PATH,
        client_id=CLIENT_ID,
        clean_session=False,
        keep_alive_secs=30
    )
    
    connect_future = conexao.connect()
    connect_future.result()
    print("Conectado!")
    return conexao

def gerar_dado_sensor():
    # Simula dados realistas de temperatura e umidade
    return {
        "deviceId": "sensor1",
        "temperatura": round(random.uniform(18.0, 35.0), 1),
        "umidade": round(random.uniform(40.0, 80.0), 1),
        "timestamp": datetime.now().isoformat(),
        "localizacao": "bedroom"
    }

def main():
    conexao = conectar()
    
    print(f"Enviando dados para o tópico: {TOPIC}")
    print("Pressiona Ctrl+C para parar\n")
    
    try:
        while True:
            dado = gerar_dado_sensor()
            
            # Publica no tópico MQTT
            conexao.publish(
                topic=TOPIC,
                payload=json.dumps(dado),
                qos=mqtt.QoS.AT_LEAST_ONCE
            )
            
            print(f"Enviado: Temp={dado['temperatura']}°C | Umidade={dado['umidade']}% | {dado['timestamp']}")
            
            # Espera 5 segundos antes de mandar o próximo
            time.sleep(5)
            
    except KeyboardInterrupt:
        print("\nParando simulador...")
    finally:
        disconnect_future = conexao.disconnect()
        disconnect_future.result()
        print("Desconectado!")

if __name__ == "__main__":
    main()