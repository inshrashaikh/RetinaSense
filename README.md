# RetinaSense

> **Smart India Hackathon (SIH) 2026 Project**

**Team:** CoreDevs  
**Problem Statement ID:** `26038`

**AI-assisted diabetic retinopathy screening and telemedicine workflow platform built with MATLAB, Deep Learning, and Simulink.**

## About the Project

RetinaSense is a working research and engineering prototype developed for **Smart India Hackathon (SIH) 2026**.

The project focuses on automated retinal image analysis and diabetic retinopathy (DR) screening by combining image processing, deep learning, explainable AI, clinical review, and district-level telemedicine simulation.

## Key Features

- Retinal image quality assessment and enhancement
- Retinal structure and lesion analysis
- DR severity grading from **0–4**
- Referable DR detection
- Calibrated confidence and uncertainty estimation
- Grad-CAM based visual explainability
- Doctor review and final decision workflow
- Automated screening reports
- Role-based dashboards for Operator, Doctor, and District Administrator
- Simulink/SimEvents based district-level workflow and capacity analysis

## System Architecture

```text
Retinal Image
     ↓
Image Quality Assessment
     ↓
Enhancement / Preprocessing
     ↓
Retinal & Lesion Analysis
     ↓
ResNet-50 DR Classification
     ↓
Calibration + Grad-CAM
     ↓
Doctor Review
     ↓
Final Decision + Report
````

### District Telemedicine Simulation

```text
Patient Arrival
      ↓
Acquisition
      ↓
Network / Bandwidth
      ↓
AI Processing
      ↓
Doctor Review
      ↓
Completed
```

## Tech Stack

### MATLAB / Simulation

* MATLAB R2026a
* Image Processing Toolbox
* Computer Vision Toolbox
* Deep Learning Toolbox
* Medical Imaging Toolbox
* Statistics and Machine Learning Toolbox
* Simulink
* SimEvents

### AI / Backend

* ResNet-50
* PyTorch
* ONNX
* Temperature Scaling
* Grad-CAM
* Python
* FastAPI
* MATLAB Engine for Python
* SQLite

### Frontend

* React
* TypeScript
* Vite

## Project Status

RetinaSense is a **runnable research/engineering prototype** with an integrated MATLAB, Python, web, database, and Simulink workflow.

The current implementation demonstrates the complete screening workflow using real retinal images and trained model artifacts. Further clinical validation and broader benchmark evaluation are required before production or clinical deployment.

## Data & Model Assets

The project uses retinal datasets including:

* APTOS 2019
* IDRiD
* DRIVE

Large datasets and trained model artifacts are **not included in the Git repository** due to dataset licensing, file size, and repository management considerations.

A fresh clone therefore requires the appropriate datasets, trained models, MATLAB/Python dependencies, and environment configuration to run the complete AI pipeline.

## Repository Structure

```text
RetinaSense/
├── backend/          # FastAPI backend and MATLAB integration
├── frontend/         # React + TypeScript application
├── matlab/            # Image processing, AI and explainability
├── simulink/          # District workflow and capacity simulation
├── data/              # External datasets and model assets
├── tests/              # Backend, frontend and integration tests
└── README.md
```

## SIH 2026

**Hackathon:** Smart India Hackathon 2026
**Team:** CoreDevs
**Problem Statement ID:** `26038`
