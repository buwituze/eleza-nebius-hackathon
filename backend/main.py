"""
main.py — FastAPI application entry point.

Run with:
    uvicorn main:app --reload --port 8000

Interactive docs: http://localhost:8000/docs
"""

from dotenv import load_dotenv
load_dotenv()

import asyncio
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from models import model_a
from routers import sessions, transcription, dialogue, triage, kiosk, doctor
from routers import auth, facilities, rooms, queue, patients, doctors
from database.database import DatabaseConnection


# Global state to track initialization
_startup_info = {
    "database_ready": False,
    "models_ready": False,
    "startup_errors": [],
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _startup_info
    _startup_info = {"database_ready": False, "models_ready": False, "startup_errors": []}
    
    # Initialize database connection pool (skip if USE_DB=false)
    if os.getenv('USE_DB', 'true').lower() != 'false':
        print("🔌 Initializing database connection pool...")
        try:
            DatabaseConnection.initialize_pool()
            # Verify connection works with a test query
            DatabaseConnection.execute_query("SELECT 1")
            print("✅ Database connected and verified")
            _startup_info["database_ready"] = True
        except Exception as e:
            error_msg = f"❌ Database connection failed: {type(e).__name__}: {e}"
            print(error_msg)
            _startup_info["database_ready"] = False
            _startup_info["startup_errors"].append(error_msg)
    else:
        print("⚠️ Database disabled (USE_DB=false)")
        _startup_info["database_ready"] = False
    
    # Load Whisper models in background with timeout protection (takes ~1-2 min)
    print("🚀 Server starting... Models will load in background")
    print("   Expect /models/status → 'loading_kinyarwanda_model' for ~30-90 seconds")
    
    async def load_models_with_timeout():
        try:
            await asyncio.wait_for(
                asyncio.to_thread(model_a.load_models),
                timeout=300  # 5 minute timeout
            )
            _startup_info["models_ready"] = True
        except asyncio.TimeoutError:
            error_msg = "❌ Model loading timed out after 5 minutes"
            print(error_msg)
            _startup_info["startup_errors"].append(error_msg)
            model_a._loading_status = "error: timeout after 5 minutes"
        except Exception as e:
            error_msg = f"❌ Model loading failed: {type(e).__name__}: {e}"
            print(error_msg)
            _startup_info["startup_errors"].append(error_msg)
            model_a._loading_status = f"error: {str(e)}"
    
    asyncio.create_task(load_models_with_timeout())
    
    yield
    
    # Cleanup on shutdown
    print("🔌 Closing database connection pool...")
    try:
        DatabaseConnection.close_pool()
        print("✅ Shutdown complete")
    except Exception as e:
        print(f"⚠️ Shutdown warning: {e}")


app = FastAPI(
    title="Hospital Pre-Consultation API",
    description="Voice-based triage pipeline for Kinyarwanda and English patients.",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware for Flutter web app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Authentication
app.include_router(auth.router)

# Internal pipeline — model-to-model orchestration
app.include_router(sessions.router)
app.include_router(transcription.router)
app.include_router(dialogue.router)
app.include_router(triage.router)

# Interface-facing — kiosk and clinician dashboard
app.include_router(kiosk.router)
app.include_router(doctor.router)

# Management APIs — facilities, rooms, queue, patients, doctors
app.include_router(facilities.router)
app.include_router(rooms.router)
app.include_router(queue.router)
app.include_router(patients.router)
app.include_router(doctors.router)


@app.get("/health")
def health():
    """Basic health check. Always returns 200 even if systems are degraded."""
    return {
        "status": "ok",
        "database_ready": _startup_info["database_ready"],
        "models_ready": _startup_info["models_ready"],
        "startup_errors": _startup_info["startup_errors"],
    }


@app.get("/startup/status")
def startup_status():
    """
    Detailed startup status. Use this to wait for server readiness.
    
    When both are true, server is ready for all endpoints.
    When database_ready=false but models_ready=true,
    use /sessions API only (transcription works, kiosk doesn't).
    """
    return {
        "database_ready": _startup_info["database_ready"],
        "models_ready": _startup_info["models_ready"],
        "startup_errors": _startup_info["startup_errors"],
        "message": (
            "✅ All systems ready"
            if (_startup_info["database_ready"] and _startup_info["models_ready"])
            else "⏳ Still initializing..." if not _startup_info["startup_errors"]
            else "❌ Startup failed - see errors"
        ),
    }


@app.get("/models/status")
def models_status():
    """Check if AI models are loaded and ready."""
    return model_a.get_models_status()
