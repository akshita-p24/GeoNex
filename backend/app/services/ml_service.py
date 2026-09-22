from typing import Dict, Any

from inference import predict_risk


class MLModelService:
    """
    M3 service wrapper around the actual M1 GeoNex ML inference engine.
    """

    def __init__(self):
        self.model_version = "v1.0"
        self.model_name = "GeoNex Random Forest Risk Engine"

    async def predict_risk(
        self,
        features: Dict[str, Any],
    ) -> Dict[str, Any]:

        static_features = features.get("static_features", {})
        dynamic_features = features.get("dynamic_features", {})

        result = predict_risk(
            static_features=static_features,
            dynamic_features=dynamic_features,
        )

        return {
            **result,
            "model_version": self.model_version,
            "model_name": self.model_name,
        }


ml_service = MLModelService()