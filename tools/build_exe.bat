@echo off
REM Build a single-file exe with PyInstaller. Run this from the tools folder.
pyinstaller --onefile --add-data "vehicle_detector_model.pkl;." --name vehicle-detector-server server.py
pause
