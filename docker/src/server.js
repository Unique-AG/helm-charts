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

const gracefulShutdown = (signal) => {
  console.log(`Received ${signal}, shutting down gracefully...`);
  
  let closedServers = 0;
  const totalServers = serverInstances.length;
  
  const checkShutdown = () => {
    if (closedServers === totalServers) {
      console.log('All servers closed successfully');
      process.exit(0);
    }
  };
  
  serverInstances.forEach(server => {
    server.close(err => {
      closedServers++;
      if (err) {
        console.error('Error closing server:', err);
      } else {
        console.log('Server closed successfully');
      }
      checkShutdown();
    });
  });

  // Force shutdown after 2 seconds for testing environments
  setTimeout(() => {
    console.error('Forcing shutdown due to timeout');
    process.exit(1);
  }, 2000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
