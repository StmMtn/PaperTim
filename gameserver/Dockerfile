FROM node:20

WORKDIR /usr/src/app

# Server
COPY ./package*.json ./
RUN npm install
COPY ./ ./

# Client
COPY ./client/Game/ ./client/Game

CMD ["node", "server.js"]
