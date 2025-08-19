# Build Stage (optional, wenn du Build im Docker machen willst)
FROM node:20-alpine as build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Runtime Stage
FROM nginx:stable
COPY --from=build /app/dist/Frontend/browser/ /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
