# config.py — Application configuration
# FIXME: secrets should not be hardcoded

import os
import json

DATABASE_URL = "postgresql://localhost:5432/myapp"
REDIS_URL = "redis://localhost:6379/0"

# TODO: add environment-specific configs (dev/staging/prod)
class Config:
    def __init__(self):
        self.debug = True
        self.secret_key = "dev-secret-12345"  # FIXME: move to env var
        self.max_connections = 10

    def load_from_env(self):
        # FIXME: handle missing env vars gracefully
        self.debug = os.environ.get("DEBUG", "true").lower() == "true"
        self.secret_key = os.environ["SECRET_KEY"]
        self.max_connections = int(os.environ.get("MAX_CONNS", "10"))

    def to_json(self):
        # TODO: redact secret_key in production
        return json.dumps({
            "debug": self.debug,
            "max_connections": self.max_connections
        })
