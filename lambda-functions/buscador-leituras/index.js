const mysql = require('mysql2/promise');

const dbConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 3306,
};

exports.handler = async (event) => { // event contem as informacoes da requisicao HTTP (path, method, headers...) (nessa Lambda o event vem do API Gateway, não do sensor como antes)
    const path = event.path;
    console.log('Endpoint chamado:', path);
  
    let connection;
    try {
      connection = await mysql.createConnection(dbConfig);

      let query;
      if (path === '/leituras/ultima') {
        query = 'SELECT * FROM leituras_sensor ORDER BY criado_em DESC LIMIT 1';
      } else {
        query = 'SELECT * FROM leituras_sensor ORDER BY criado_em DESC';
      }
  
      const [rows] = await connection.execute(query);

      // Retorna os dados em formato JSON e fecha a conexao
      return {
        statusCode: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify(rows)
      };
  
    } catch (error) {
      console.error('Erro:', error);
      return {
        statusCode: 500,
        body: JSON.stringify({ error: 'Erro interno' })
      };
    } finally {
      if (connection) await connection.end();
    }
  };