FROM debian:buster-slim
ARG CKAN_VERSION=ckan-2.10.3

# Internals, you probably don't need to change these
ENV TZ=UTC
ENV APP_DIR=/srv/app
ENV SRC_DIR=/srv/app/src
ENV CKAN_INI=${APP_DIR}/ckan.ini
ENV PIP_SRC=${SRC_DIR}
ENV CKAN_STORAGE_PATH=/var/lib/ckan
ENV GIT_URL=https://github.com/ckan/ckan.git
# CKAN version to build
ENV GIT_BRANCH=${CKAN_VERSION}
# Customize these on the .env file if needed
ENV CKAN_SITE_URL=http://localhost:5000
ENV CKAN__PLUGINS=image_view text_view recline_view datastore envvars

# UWSGI options
ENV UWSGI_HARAKIRI=50

WORKDIR ${APP_DIR}

# Set up timezone
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tzdata && \
    rm -rf /var/lib/apt/lists/* && \
    echo ${TZ} > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata

# Install necessary packages to run CKAN
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        gettext \
        postgresql-client \
        python3 \
        libxml2 \
        libxslt1-dev \
        python3-dev \
        python3-pip \
        libpq-dev \
        gcc \
        make \
        uwsgi \
        uwsgi-plugin-python3 \
        libmagic1 \
        curl \
        patch \
        bash && \
    rm -rf /var/lib/apt/lists/*

# Create SRC_DIR
RUN mkdir -p ${SRC_DIR}

# Install supervisord
RUN pip3 install supervisor && \
    mkdir /etc/supervisord.d

COPY setup/supervisord.conf /etc

# Install CKAN
RUN pip3 install -e git+${GIT_URL}@${GIT_BRANCH}#egg=ckan && \
    cd ${SRC_DIR}/ckan && \
    cp who.ini ${APP_DIR} && \
    pip3 install --no-binary markdown -r requirements.txt && \
    pip3 install -e git+https://github.com/okfn/ckanext-envvars.git#egg=ckanext-envvars && \
    ckan generate config ${CKAN_INI} && \
    ckan config-tool ${CKAN_INI} "beaker.session.secret = " && \
    ckan config-tool ${CKAN_INI} "ckan.plugins = ${CKAN__PLUGINS}"

# Create a local user and group to run the app
RUN groupadd -r ckan && \
    useradd -r -g ckan ckan

# Create local storage folder
RUN mkdir -p ${CKAN_STORAGE_PATH} && \
    chown -R ckan:ckan ${CKAN_STORAGE_PATH}

COPY setup/prerun.py ${APP_DIR}
COPY setup/start_ckan.sh ${APP_DIR}
ADD https://raw.githubusercontent.com/ckan/ckan/${GIT_BRANCH}/wsgi.py ${APP_DIR}
RUN chmod 644 ${APP_DIR}/wsgi.py

# Create entrypoint directory for children image scripts
ONBUILD RUN mkdir /docker-entrypoint.d

EXPOSE 5000

HEALTHCHECK --interval=60s --timeout=5s --retries=5 CMD curl --fail http://localhost:5000/api/3/action/status_show || exit CMD ["/srv/app/start_ckan.sh"]

CMD ["/srv/app/start_ckan.sh"]
