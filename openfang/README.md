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
- `.env` file mounted read-only
- No secrets baked into the Docker image
- Optional: works without `.env` file

## Files

- `entrypoint.sh` - Filters and injects env vars at runtime
- `Dockerfile` - Extends official OpenFang image
