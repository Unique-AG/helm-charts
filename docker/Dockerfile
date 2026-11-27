FROM node:26.13.1-trixie-slim@sha256:e6bedef217677b276c591795e169840edd9096dbf13f29df8ef8d1856b8820bc
WORKDIR /app
COPY src/server.js .
EXPOSE 8080 3000
USER node
CMD ["node", "server.js"]
