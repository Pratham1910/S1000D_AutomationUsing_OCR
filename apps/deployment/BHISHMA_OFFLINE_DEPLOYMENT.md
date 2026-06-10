# Bhishma beta version - Offline Docker Deployment

This deployment mode is designed for on-site local testing with Docker.

## What is included

- Backend image: `bhishma-beta-backend:latest`
- Frontend image: `bhishma-beta-frontend:latest`
- All Python/Node dependencies are packaged inside the Docker image layers.
- Image bundle TAR: `apps/deployment/dist/bhishma-beta-images.tar`

## One-time bundle build (online machine)

Run:

```bat
apps\deployment\bhishma_build_bundle.bat
```

This builds images and creates:

- `apps/deployment/dist/bhishma-beta-images.tar`

Copy the TAR and deployment folder to the offline target machine.

## Offline deployment (target machine)

Run:

```bat
apps\deployment\bhishma_deploy_offline.bat
```

Before using the backend, start the local OCR service in a separate terminal:

```bat
apps\deployment\bhishma_start_ocr_service.bat
```

## Service URLs

- Frontend: `http://localhost:3000`
- Backend: `http://localhost:8000`
- API Docs: `http://localhost:8000/docs`

## Online/offline behavior

Current Bhishma app stack itself does not call cloud OCR APIs by default.

Potential online usage only occurs if:

1. You explicitly configure the OCR layer to use cloud MaaS APIs.
2. You use a remote OCR endpoint in `custom_url`.

Default OCR URL for this deployment:

- `http://host.docker.internal:5002/glmocr/parse`

So OCR remains local as long as your OCR service on port 5002 is local.

## Important note

The frontend PDF viewer was updated to use a local PDF worker (no CDN fetch), so PDF preview works in offline mode.
