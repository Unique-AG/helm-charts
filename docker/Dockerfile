FROM node:25-bookworm-slim
WORKDIR /app
COPY src/server.js .
EXPOSE 8080 3000
USER node
CMD ["node", "server.js"]
