# Dockerfile

# ---- Builder Stage ----
# Use official Node.js Alpine image for a smaller base
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY app/package*.json ./

# Install dependencies for building the application
RUN npm ci --only=production

# Copy application source code
COPY app/ ./

# ---- Runner Stage ----
# Use a distroless image for minimal attack surface in production
FROM gcr.io/distroless/nodejs20-debian11

# Set working directory
WORKDIR /app

# Create a non-root user for security
USER nonroot
WORKDIR /home/nonroot

# Copy built artifacts from the builder stage
COPY --from=builder --chown=nonroot:nonroot /app/node_modules ./node_modules
COPY --from=builder --chown=nonroot:nonroot /app/src ./src

# Set environment variables for production
ENV NODE_ENV=production
ENV PORT=3000

# Expose port 3000
EXPOSE 3000

# Add a healthcheck to ensure the application is running correctly
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD [ "node", "-e", "require('http').get('http://localhost:3000/health', (res) => { if (res.statusCode !== 200) process.exit(1); }).on('error', () => process.exit(1));" ]

# Command to run the application
CMD ["src/server.js"]