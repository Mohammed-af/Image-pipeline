import PIL
from open_clip.transform import PreprocessCfg, image_transform_v2
from open_clip import get_tokenizer
import tritonclient.grpc as grpcclient
from inference.trition_utils import trition_infer_request
import torch
from models import EmbeddingResponse
import numpy as np
import os

# Read from environment variables with defaults
cache_dir = os.getenv("CACHE_DIR", "/app/cache_token")
triton_server_url = os.getenv("TRITON_SERVER_URL", "localhost:8001")


class BaseEmbedding:
    """Base class for embedding handlers."""
    def compute_image_embedding(self, data: list[PIL.Image]) -> list[EmbeddingResponse]:
        """Computes image embeddings."""
        pass

    def compute_text_embedding(self, data: list[str]) -> list[EmbeddingResponse]:
        """Computes text embeddings."""
        pass


class TritionSigLIPEmbedding(BaseEmbedding):
    def __init__(
        self,
        triton_server_url: str,
    ):
        self.text_model_name = "SigLIP_text"
        self.image_model_name = "SigLIP_image"
        self.triton_server_url = triton_server_url
        self.client = grpcclient.InferenceServerClient(url=self.triton_server_url)
        preprocess_cfg = PreprocessCfg(
            size=(384, 384),
            interpolation="bicubic",
            resize_mode="squash",
            mean=(0.5, 0.5, 0.5),
            std=(0.5, 0.5, 0.5),
        )
        self.image_processor = image_transform_v2(preprocess_cfg, is_train=False)
        self.tokenizer = get_tokenizer(
            "ViT-SO400M-14-SigLIP-384", cache_dir=cache_dir, local_files_only=True
        )

    def compute_image_embedding(self, data: list[PIL.Image]) -> list[EmbeddingResponse]:
        data = torch.stack([self.image_processor(datum) for datum in data]).numpy()
        inputs = {"input0": data}
        results = trition_infer_request(
            self.client, self.image_model_name, inputs, "FP32"
        )
        embeddings = results.as_numpy("output0").tolist()
        return [
            EmbeddingResponse(embedding=embedding, metadata=None)
            for embedding in embeddings
        ]

    def compute_text_embedding(self, data: list[str]) -> list[EmbeddingResponse]:
        data = torch.stack([self.tokenizer(datum).squeeze() for datum in data]).numpy()
        inputs = {"input": data}
        results = trition_infer_request(
            self.client, self.text_model_name, inputs, "INT64"
        )
        embeddings = results.as_numpy("output").tolist()
        return [
            EmbeddingResponse(embedding=embedding, metadata=None)
            for embedding in embeddings
        ]
