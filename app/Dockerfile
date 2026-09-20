FROM python:3.12-slim

# No third party dependencies: the service uses only the Python standard
# library, so no `pip install` step or requirements.txt is needed.

WORKDIR /app

# --chmod explicitly makes the file world readable inside the image, no
# matter what permissions it had on the host machine that built it.
# Without this, COPY keeps the source file's host permissions as is. If
# app.py happens to be owner only (no read for group or other) on the
# build machine, the non root `appuser` below can't open it, and the
# container fails at startup with "Permission denied".
COPY --chmod=644 app.py .

ENV PYTHONUNBUFFERED=1 \
    PORT=8080 \
    SERVICE_NAME=mainspring-energy-service

# Run as a non root user.
RUN useradd --no-create-home --uid 10001 appuser
USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
