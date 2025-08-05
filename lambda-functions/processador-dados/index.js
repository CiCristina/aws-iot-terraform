exports.handler = async (event) => {
    console.log('Recebi dados:', JSON.stringify(event, null, 2));
    
    // Processar cada record do Kinesis
    for (const record of event.Records) {
        // Decodificar dados do Kinesis
        const payload = Buffer.from(record.kinesis.data, 'base64').toString();
        console.log('Dados do sensor:', payload);
        
        try {
            const dadosSensor = JSON.parse(payload);
            
            // Aqui você faria algum processamento
            console.log(`Temperatura: ${dadosSensor.temperatura}°C`);
            console.log(`Umidade: ${dadosSensor.umidade}%`);
            
            // Por enquanto só loga, depois vamos salvar no banco
            
        } catch (error) {
            console.error('Erro ao processar dados:', error);
        }
    }
    
    return {
        statusCode: 200,
        body: 'Dados processados com sucesso!'
    };
};
