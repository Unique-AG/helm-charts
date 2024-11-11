const http = require('http');

const hostname = '0.0.0.0';
const servers = [
  {
    mimicking: 'backend-service',
    port: 8080,
    handler: 
    (req, res) => {
      if (req.url === '/probe' && req.method === 'GET') {
        res.statusCode = 200;
        res.setHeader('Content-Type', 'text/plain');
        res.end('OK');
      } else {
        res.statusCode = 404;
        res.setHeader('Content-Type', 'text/plain');
        res.end('Not Found');
      }
    }
  },
  {
    mimicking: 'web-app',
    port: 3000,
    handler: 
    (req, res) => {
      if (req.url === '/api/health' && req.method === 'GET') {
        res.statusCode = 200;
        res.setHeader('Content-Type', 'text/plain');
        res.end('OK');
      } else {
        res.statusCode = 404;
        res.setHeader('Content-Type', 'text/plain');
        res.end('Not Found');
      }
    }
  },
];

const serverInstances = [];

servers.forEach(srv => {
  const server = http.createServer(srv.handler);
  server.listen(srv.port, hostname, () => {
    console.log(`Server running at http://${hostname}:${srv.port}/ mimicking ${srv.mimicking}`);
  });
  serverInstances.push(server);
});

process.on('SIGTERM', () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  serverInstances.forEach(server => {
    server.close(err => {
      if (err) {
        console.error('Error closing server:', err);
        process.exit(1);
      } else {
        console.log('Server closed successfully');
      }
    });
  });

  setTimeout(() => {
    console.error('Forcing shutdown due to timeout');
    process.exit(1);
  }, 10000);
});
