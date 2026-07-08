"""Minimal sample API for the reference platform.

Deliberately tiny — the point of this repo is the *infrastructure* around it,
not the app. It exposes a health check (used by the ALB) and a root endpoint,
and reads DATABASE_URL from the environment (injected from SSM by ECS).
"""

import os

from fastapi import FastAPI

app = FastAPI(title="prod-saas-aws sample app")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/")
def root() -> dict[str, str]:
    return {
        "message": "Running on ECS Fargate behind an ALB.",
        "environment": os.getenv("ENVIRONMENT", "local"),
        "database_configured": str(bool(os.getenv("DATABASE_URL"))),
    }
