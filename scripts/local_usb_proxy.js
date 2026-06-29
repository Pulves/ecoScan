const net = require('net');

const listenHost = '127.0.0.1';
const listenPort = 8000;
const targetHost = '127.0.0.1';
const targetPort = 18000;

const server = net.createServer((client) => {
  console.log(`Conexao recebida de ${client.remoteAddress}:${client.remotePort}`);
  const upstream = net.createConnection({ host: targetHost, port: targetPort });

  client.once('data', (data) => {
    console.log(`Relay recebeu ${data.length} bytes do dispositivo`);
  });
  upstream.once('data', (data) => {
    console.log(`API respondeu ${data.length} bytes ao relay`);
  });

  client.pipe(upstream);
  upstream.pipe(client);

  client.on('error', () => upstream.destroy());
  upstream.on('error', (error) => {
    console.error(`Falha ao acessar a API Docker: ${error.message}`);
    client.destroy();
  });
});

server.on('error', (error) => {
  console.error(`Falha no relay USB local: ${error.message}`);
  process.exitCode = 1;
});

server.listen(listenPort, listenHost, () => {
  console.log(
    `Relay EcoScan ativo em ${listenHost}:${listenPort} -> ${targetHost}:${targetPort}`,
  );
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
