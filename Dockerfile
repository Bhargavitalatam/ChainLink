# Use a Node.js base image
FROM node:18

# Set the working directory
WORKDIR /usr/src/app

# Copy package.json
COPY package.json ./

# Install dependencies (Skipped, copying from host for reliability)
# RUN npm install --no-package-lock --no-audit --no-fund --loglevel=info

# Copy the rest of the application code
COPY . .

# Command to keep the container running
CMD ["tail", "-f", "/dev/null"]
