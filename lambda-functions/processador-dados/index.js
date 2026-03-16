// Lambda recebe dados do sensor e precisa salvar no banco. Quais são os 3 passos lógicos que ela precisa fazer, em ordem? abrir, salvar e fechar
//Primeiro passo — importar a biblioteca e configurar a conexão.
const mysql = require('mysql2/promise');

const dbConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 3306,
};

exports.handler = async (event) => {   //event e justamente o dado que o sensor mandou
  console.log('Recebi dados:', JSON.stringify(event, null, 2));

  let connection;
  try {
    connection = await mysql.createConnection(dbConfig);

    // Cria a tabela se não existir
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS leituras_sensor (
        id INT AUTO_INCREMENT PRIMARY KEY,
        device_id VARCHAR(50),
        temperatura DECIMAL(5,2),
        umidade DECIMAL(5,2),
        localizacao VARCHAR(100),
        timestamp_sensor VARCHAR(50),
        criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Insere os dados recebidos
    await connection.execute(
      `INSERT INTO leituras_sensor 
       (device_id, temperatura, umidade, localizacao, timestamp_sensor)
       VALUES (?, ?, ?, ?, ?)`, // Os ? são placeholders, marcadores de posicao. N foi escrito de outra forma p n abrir brecha p SQL Injection
      [
        event.deviceId,
        event.temperatura,
        event.umidade,
        event.localizacao,
        event.timestamp,
      ]
    );

    console.log(`Dados salvos: ${event.deviceId} - ${event.temperatura}°C`);
    return { statusCode: 200, body: 'Dados salvos com sucesso!' };

  } 
  catch (error) {
    console.error('Erro:', error);
    throw error;
  } finally {
    if (connection) await connection.end(); 
  }
};

