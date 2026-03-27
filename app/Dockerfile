FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create static dir
RUN mkdir -p static

# Expose port
EXPOSE 8000

# Run the server (sync pipeline runs as a background thread inside the server)
CMD ["uvicorn", "src.server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
