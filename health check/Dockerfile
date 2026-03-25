FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 unixodbc-dev ca-certificates

RUN curl -fsSLk https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg

RUN echo "deb [signed-by=/usr/share/keyrings/microsoft-prod.gpg trusted=yes] https://packages.microsoft.com/debian/12/prod bookworm main" \
    > /etc/apt/sources.list.d/mssql-release.list

RUN echo 'Acquire::https::packages.microsoft.com::Verify-Peer "false";' \
    > /etc/apt/apt.conf.d/99microsoft-ssl

RUN apt-get update && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt

COPY app.py .

RUN useradd -m appuser
USER appuser

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]