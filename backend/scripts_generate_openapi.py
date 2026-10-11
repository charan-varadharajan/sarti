import importlib
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BACKEND_ROOT / "src"))

app = importlib.import_module("sarti_backend.main").app

(BACKEND_ROOT / "openapi.json").write_text(
    json.dumps(app.openapi(), indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
