# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QuakeWatch is a Flask-based web application that displays real-time and historical earthquake data from the USGS API. The project is containerized with Docker and deployed to Kubernetes using Minikube.

## Architecture

- **Flask Application**: Located in `QuakeWatch/` directory
  - `app.py`: Application factory with logging configuration
  - `dashboard.py`: Blueprint with routes using OOP pattern (EarthquakeDashboard class)  
  - `utils.py`: Helper functions for data processing, graph generation, and Jinja2 filters
  - `templates/`: Jinja2 HTML templates (base.html, main_page.html, graph_dashboard.html)
  - `static/`: Static assets including logo

- **Data Source**: USGS Earthquake API for real-time earthquake data
- **Visualization**: Matplotlib with 'Agg' backend for headless graph generation
- **Deployment**: Docker + Kubernetes with production-ready configuration

## Development Commands

### Local Development
```bash
cd QuakeWatch
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```
Application runs on http://127.0.0.1:5000

### Docker Development
```bash
docker-compose up --build
```
Application runs on http://localhost:8000

### Production Deployment
```bash
chmod +x build-deploy.sh
./build-deploy.sh
```

This script:
1. Starts Minikube with Docker driver
2. Enables required addons (storage-provisioner, default-storageclass, metrics-server)
3. Applies Kubernetes secrets from `earthquake-secret.yaml`
4. Deploys the application using `deploy.yaml`
5. Opens the service in browser via `minikube service earthquake-service`

### Kubernetes Resources
- **Deployment**: 3 replicas with resource limits, health checks, and HPA (2-5 replicas based on CPU)
- **Service**: NodePort on port 32000
- **ConfigMap**: Application configuration
- **Secret**: API keys (earthquake-secret.yaml)
- **PVC**: Shared logs storage (1Gi)
- **CronJob**: Date logger running every minute

## Key Implementation Details

- **Matplotlib Backend**: Must use `matplotlib.use('Agg')` before any imports to avoid GUI issues
- **Logging**: Rotating file handlers for error.log and access.log in `logs/` directory
- **Custom Filter**: `timestamp_to_str` converts USGS epoch timestamps to readable format
- **Location Support**: Predefined locations in COUNTRIES dict (Tel Aviv, California, Japan, Indonesia, Chile)
- **Docker Image**: Published as `blaqr/earthquake:latest` on Docker Hub

## API Endpoints

- `/`: Main page
- `/graph-earthquakes`: Dashboard with graphs and earthquake data
- `/graph-earthquakes.png`: Dynamic graph image generation
- `/telaviv-earthquakes`: Raw earthquake data for Tel Aviv region
- `/ping`, `/health`, `/status`, `/info`: Health check endpoints

## Dependencies

Python dependencies in `QuakeWatch/requirements.txt`:
- Flask (web framework)
- requests (USGS API calls)
- matplotlib (graph generation)