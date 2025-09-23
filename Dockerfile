FROM rocker/shiny:4.1.2 

# Installer dépendances système nécessaires
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Installer remotes
RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org')"

# Installer les packages nécessaires
RUN R -e "remotes::install_cran(c( \
    'shiny', 'plotly', 'DT', 'readr', 'dplyr', 'tidyr', \
    'lubridate', 'scales', 'cachem', 'digest' \
  ))"

# Supprimer tout le contenu par défaut de Shiny Server
RUN rm -rf /srv/shiny-server/*

# Copier ton application directement à la racine
COPY . /srv/shiny-server/

# Donner les bons droits
RUN chown -R shiny:shiny /srv/shiny-server

# Exposer le port Shiny
EXPOSE 3838

# Lancer Shiny Server
CMD ["/usr/bin/shiny-server"]
