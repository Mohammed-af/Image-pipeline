from models import EmbeddingRequest, EmbeddingResponse
import PIL
from io import BytesIO
import base64
from inference.embeddings import TritionSigLIPEmbedding
import os

# Read from environment variable with default
triton_server_url = os.getenv("TRITON_SERVER_URL", "0.0.0.0:8001")


def __base64_to_PIL(data: list[str]) -> list[PIL.Image]:
    return [
        PIL.Image.open(BytesIO(base64.b64decode(datum, validate=True)))
        for datum in data
    ]


def image_embedding_request_handler(
    request: EmbeddingRequest, model_name: str
) -> list[EmbeddingResponse]:
    images = __base64_to_PIL(request.data)
    embedding_backends = {
        "SigLIP": TritionSigLIPEmbedding(triton_server_url=triton_server_url)
    }
    return embedding_backends[model_name].compute_image_embedding(images)


def text_embedding_request_handler(
    request: EmbeddingRequest, model_name: str
) -> list[EmbeddingResponse]:
    embedding_backends = {
        "SigLIP": TritionSigLIPEmbedding(triton_server_url=triton_server_url)
    }
    return embedding_backends[model_name].compute_text_embedding(request.data)
