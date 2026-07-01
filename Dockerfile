FROM mcr.microsoft.com/dotnet/sdk:9.0

WORKDIR /app

# Projektdateien kopieren
COPY . .

# INI-Datei umbenennen
RUN mv settings.Systec-IT1000.ini settings.ini
RUN sed -i 's|listen = http://127.0.0.1:5000|listen = http://0.0.0.0:5000|' settings.ini

# Anwendung starten
CMD ["dotnet", "run"]
