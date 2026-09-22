from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from inference import predict_risk


app = FastAPI(
    title="GeoNex Landslide Risk API",
    version="1.0.0",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class RiskRequest(BaseModel):
    static_features: dict
    dynamic_features: dict


@app.get("/")
def root():
    return {
        "status": "ok",
        "service": "GeoNex Landslide Risk API",
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "ml": "loaded",
    }


@app.post("/predict")
def predict(request: RiskRequest):
    try:
        result = predict_risk(
            request.static_features,
            request.dynamic_features,
        )

        return result

    except ValueError as e:
        raise HTTPException(
            status_code=400,
            detail=str(e),
        )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=str(e),
        )