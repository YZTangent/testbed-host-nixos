#!/usr/bin/env bash
set -euo pipefail

echo "==> Setting up GROD / Safari Python 3.12 environment..."

# 1. Create Python 3.12 virtual environment
VENV_DIR="$HOME/.venv/safari"
if [ ! -d "$VENV_DIR" ]; then
    python3.12 -m venv "$VENV_DIR"
    echo "Created virtualenv at $VENV_DIR"
fi

# 2. Activate
source "$VENV_DIR/bin/activate"

# 3. Upgrade pip and install PyTorch with CUDA 12.8 (Blackwell sm_120 support)
echo "==> Installing PyTorch CUDA 12.8..."
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128

# 4. Install Safari SDK, LeRobot, and dependencies
echo "==> Installing Safari SDK and LeRobot..."
pip install safari-sdk
pip install git+https://github.com/huggingface/lerobot.git
pip install absl-py datasets "lerobot[dataset]"

# 5. Setup config directory for API key
mkdir -p "$HOME/.config/safari_sdk"
if [ ! -f "$HOME/.config/safari_sdk/API_KEY" ]; then
    touch "$HOME/.config/safari_sdk/API_KEY"
    chmod 600 "$HOME/.config/safari_sdk/API_KEY"
    echo "Placeholder created at ~/.config/safari_sdk/API_KEY (paste your Gemini Robotics API key here)"
fi

echo "==> Setup complete! To activate: source ~/.venv/safari/bin/activate (or run 'safari-env')"
