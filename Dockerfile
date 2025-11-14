# Install dependencies only when needed
FROM node:20-alpine AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Enable pnpm with specific version
RUN corepack enable
RUN corepack prepare pnpm@10.0.0 --activate

# Copy lockfile and package.json
COPY package.json pnpm-lock.yaml* ./

# Install dependencies with frozen lockfile
RUN pnpm i --frozen-lockfile

# Rebuild the source code only when needed
FROM node:20-alpine AS builder
WORKDIR /app

# Set environment variables for build optimization
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV NEXT_TURBO_CACHE_MEMORY_MULTIPLIER=4

# Install build dependencies
RUN apk add --no-cache libc6-compat
RUN corepack enable
RUN corepack prepare pnpm@10.0.0 --activate

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy project files
COPY . .

# Build the application with optimized settings
RUN pnpm run build

# Production image, copy all the files and run next
FROM node:20-alpine AS runner
WORKDIR /app

# Install runtime dependencies for image optimization
RUN apk add --no-cache \
    libc6-compat \
    dumb-init \
    curl

# Create non-root user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Set consistent environment variables
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_OPTIONS="--max-old-space-size=512"
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Copy public directory and standalone build
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

EXPOSE 3000

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# server.js is created by next build from the standalone output
CMD ["node", "server.js"]