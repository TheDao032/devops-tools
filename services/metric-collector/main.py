import psutil

from prometheus_client import start_http_server, Gauge
from fastapi import APIRouter, FastAPI

from config.config import settings
from internal.api.http import route

from internal.application.metrics import create_metrics_handler

root_router = APIRouter()

app = FastAPI(
    title=settings.API_NAME,
    openurl_api=f"${settings.API_V1_STR}/${settings.API_DOC}"
)


@root_router.get("/ping", status_code=200, tags=["health-check"])
async def health_check():
    return {"message": "pong"}


app.include_router(route.api_router, prefix=settings.API_V1_STR)
app.include_router(root_router)

# Prometheus start server & collect metrics
def metric_collector():
    start_http_server(settings.prometheus.PORT)
    create_metrics_handler.collect_metrics(settings.prometheus.COLLECT_METRIC_TIME)

prometheus = metric_collector()
