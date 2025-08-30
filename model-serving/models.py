from pydantic import BaseModel
from typing import Optional, Any

# ---------------------------------
# Request Models
# ---------------------------------
class EmbeddingRequest(BaseModel):
    data: list[str]

# ---------------------------------
# Response Models
# ---------------------------------
class EmbeddingResponse(BaseModel):
    embedding: list[float]
    metadata: Optional[dict[str,Any]] = None 