# syntax=docker/dockerfile:1

ARG NODE_VERSION=20.19.0
ARG NGINX_VERSION=1.27

# =========================================
# Stage 1: Build the Angular Application
# =========================================
# Use a lightweight Node.js image for building (customizable via ARG)
FROM node:${NODE_VERSION}-alpine AS builder
# Set the working directory inside the container
WORKDIR /app
# Copy package-related files first to leverage Docker's caching mechanism
COPY package.json package-lock.json ./
# Install project dependencies using npm ci (ensures a clean, reproducible install)
RUN --mount=type=cache,target=/root/.npm npm ci
# Copy the rest of the application source code into the container
COPY . .
# Build the Angular application
RUN npm run build -- --configuration production

# =========================================
# Stage 2: Prepare Nginx to Serve Static Files
# =========================================
# Use a lightweight Nginx image for building (customizable via ARG)
FROM nginx:${NGINX_VERSION}-alpine AS final
# Copy custom Nginx config
COPY nginx/nginx.conf /etc/nginx/nginx.conf
# Copy the static build output from the build stage to Nginx's default HTML serving directory
COPY --chown=nginx:nginx --from=builder /app/dist/*/browser /app
# Use a built-in non-root user for security best practices
USER nginx
# Expose port 80 to allow HTTP traffic
EXPOSE 80
# Start Nginx directly with custom config
ENTRYPOINT ["nginx", "-c", "/etc/nginx/nginx.conf"]
CMD ["-g", "daemon off;"]