# Use Node.js official image as base image
FROM node:lts-alpine AS build-stage

# Set working directory
WORKDIR /app

# Ensure devDependencies are installed during build stage
ENV NODE_ENV=development

# Copy package manifests
COPY package.json pnpm-lock.yaml ./

# Enable corepack and install pnpm compatible with lockfileVersion 9
RUN corepack enable && corepack prepare pnpm@10 --activate
# Install all dependencies needed for build (including devDependencies)
RUN pnpm install --frozen-lockfile

# Copy project files
COPY . .

# Build project, stage PDF worker, and cleanup cache
RUN pnpm build && \
    mkdir -p /tmp/pdfworker && \
    cp node_modules/pdfjs-dist/build/pdf.worker.min.mjs /tmp/pdfworker/pdf.worker.min.mjs && \
    pnpm store prune && \
    rm -rf node_modules

# Use Nginx image as runtime image
FROM nginx:stable-alpine AS production-stage

# Copy build output to Nginx web root
COPY --from=build-stage /app/dist /usr/share/nginx/html

# Copy PDF.js worker as a stable offline path
COPY --from=build-stage /tmp/pdfworker/pdf.worker.min.mjs /usr/share/nginx/html/assets/pdf.worker.min.mjs

# Copy Nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Add health check (index.html exists)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD test -f /usr/share/nginx/html/index.html || exit 1

# Expose port 80
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
