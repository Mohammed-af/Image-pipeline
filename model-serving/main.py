from fastapi import FastAPI
import endpoints

app = FastAPI(
    title="Crossmodal Search API",
    description="API for text and image embeddings using SigLIP models via Triton Server",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Health check endpoint for Docker health checks
@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "crossmodal-search-api"}

app.include_router(endpoints.router)


def main():
    pass


if __name__ == "__main__":
    # To run the app for development, you would typically use:
    # uvicorn main:app --reload
    main()
