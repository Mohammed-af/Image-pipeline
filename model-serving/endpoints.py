from fastapi import APIRouter
import models
import handlers

router = APIRouter()


@router.post("/retrieval/{model_name}/embed-text")
def embed_text(
    model_name: str, request: models.EmbeddingRequest
) -> list[models.EmbeddingResponse]:
    return handlers.text_embedding_request_handler(request, model_name)


@router.post("/retrieval/{model_name}/embed-image")
def embed_image(
    model_name: str, request: models.EmbeddingRequest
) -> list[models.EmbeddingResponse]:
    return handlers.image_embedding_request_handler(request, model_name)