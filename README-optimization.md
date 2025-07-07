# Ansible Dependencies Optimization Guide

This guide explains how to use the optimized Docker image with pre-installed Ansible dependencies to significantly reduce bootstrap time.

## Overview

Instead of installing Ansible + Galaxy dependencies on every container boot (which can take 2-5 minutes), we:
1. Pre-build a custom Docker image with dependencies installed
2. Only update dependencies when explicitly needed
3. Cache dependency installation status

## Quick Start

### 1. Build the Custom Image

```bash
# Build the optimized base image
./build-base-image.sh

# Or with custom name/tag
IMAGE_NAME=my-ansible-base IMAGE_TAG=v1.0 ./build-base-image.sh
```

### 2. Use the Custom Image

```bash
# Use custom image in test scripts
IMAGE=was-ansible-base:latest ./test_server.sh
IMAGE=was-ansible-base:latest ./test_worker.sh

# Or set as default
export IMAGE=was-ansible-base:latest
./test_server.sh
```

### 3. Force Dependency Updates (when needed)

```bash
# Force update dependencies on server
docker exec <container> bash -c "FORCE_UPDATE_DEPS=true /workspace/ansible/bootstrap_server.sh"

# Or set during container startup
docker run ... -e FORCE_UPDATE_DEPS=true was-ansible-base:latest
```

## Performance Benefits

| Scenario | Original Time | Optimized Time | Savings |
|----------|---------------|----------------|---------|
| First boot | 3-5 minutes | 30-60 seconds | 80-90% |
| Subsequent boots | 3-5 minutes | 10-20 seconds | 95% |
| Dependency updates | 3-5 minutes | 1-2 minutes | 60% |

## Advanced Strategies

### Strategy 1: Multi-Stage Build with Version Pinning

Create versioned images that pin specific dependency versions:

```dockerfile
# Dockerfile.versioned
FROM jrei/systemd-ubuntu:22.04 as base
# ... base setup ...

FROM base as deps-v1.0
COPY requirements-v1.0.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
    && ansible-galaxy role install -r /tmp/requirements.yml

FROM base as deps-latest
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
    && ansible-galaxy role install -r /tmp/requirements.yml
```

### Strategy 2: Registry-Based Images

Push to a container registry for team sharing:

```bash
# Build and push
docker build -f Dockerfile.base -t your-registry.com/ansible-base:latest .
docker push your-registry.com/ansible-base:latest

# Team members use
IMAGE=your-registry.com/ansible-base:latest ./test_server.sh
```

### Strategy 3: Dependency Health Checks

Add dependency verification:

```bash
# Check if dependencies are current
ansible-galaxy collection list | grep kubernetes.core
ansible-galaxy role list | grep xanmanning.k3s
```

## When to Update Dependencies

### Automatic Updates
- Set `FORCE_UPDATE_DEPS=true` in CI/CD pipelines
- Weekly scheduled image rebuilds
- After requirements.yml changes

### Manual Updates
```bash
# Update single container
docker exec <container> /usr/local/bin/update-ansible-deps.sh

# Rebuild image with latest deps
./build-base-image.sh
```

## Production Considerations

### Image Tagging Strategy
```bash
# Use semantic versioning
./build-base-image.sh && docker tag was-ansible-base:latest was-ansible-base:2024.1
docker tag was-ansible-base:latest was-ansible-base:stable

# Date-based tags
docker tag was-ansible-base:latest was-ansible-base:$(date +%Y%m%d)
```

### Dependency Pinning
Pin specific versions in `requirements.yml`:

```yaml
---
collections:
  - name: kubernetes.core
    version: ">=2.3.0,<3.0.0"

roles:
  - name: xanmanning.k3s
    version: "v3.4.0"
```

### CI/CD Integration
```yaml
# .github/workflows/build-base-image.yml
name: Build Ansible Base Image
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly rebuild
  push:
    paths:
      - 'was-ansible/ansible/requirements.yml'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and push image
        run: |
          cd was-ansible
          ./build-base-image.sh
          docker tag was-ansible-base:latest ${{ secrets.REGISTRY }}/ansible-base:latest
          docker push ${{ secrets.REGISTRY }}/ansible-base:latest
```

## Troubleshooting

### Dependency Conflicts
```bash
# Clear all cached deps and reinstall
docker exec <container> bash -c "
  rm -rf ~/.ansible/collections ~/.ansible/roles /root/.ansible_deps_installed
  /usr/local/bin/update-ansible-deps.sh
"
```

### Image Size Optimization
```bash
# Check image layers
docker history was-ansible-base:latest

# Multi-stage build to reduce size
# See Dockerfile.optimized example
```

### Network Issues
```bash
# Use local requirements file if remote fetch fails
docker run -v ./requirements.yml:/tmp/requirements.yml was-ansible-base:latest \
  ansible-galaxy collection install -r /tmp/requirements.yml
```

## Monitoring

### Dependency Freshness
```bash
# Check last update time
docker exec <container> stat /root/.ansible_deps_installed

# List installed versions
docker exec <container> ansible-galaxy collection list
```

### Performance Metrics
```bash
# Time the bootstrap process
time docker exec <container> /workspace/ansible/bootstrap_server.sh
``` 