# OpenFang Environment Variable Injection

Secure runtime injection of user-defined environment variables into OpenFang service.

## Usage

1. Create `.env` with `OPENFANG_*` variables, for example:

```env
OPENFANG_API_KEY=sk-your-key
OPENFANG_MODEL=custom-model
```

2. Build and run:

```bash
./bin/cli cluster build
./bin/cli cluster start
```

## Security

- Only `OPENFANG_*` variables are injected into the container
- `.env` file mounted read-only (optional)
- No secrets baked into the Docker image

## Files

- `entrypoint.sh` - Filters and injects env vars at runtime
- `Dockerfile` - Extends official OpenFang image with empty `.env`
- `.env` (optional) - User-defined environment variables

## How It Works

1. Dockerfile creates an empty `/data/.env` file
2. docker-compose can optionally mount user's `.env` to override it
3. Entrypoint checks if `.env` is a file and processes only `OPENFANG_*` vars
4. If no `.env` mounted, container starts with empty environment