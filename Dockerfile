FROM httpd:2.4.41-alpine

## install ruby 2.7
## https://github.com/docker-library/ruby/blob/82eecb7596c3cb466dd87d4b0350d189a330b925/2.7/alpine3.11/Dockerfile

RUN apk add --no-cache \
    gmp-dev

# skip installing gem documentation
RUN set -eux; \
    mkdir -p /usr/local/etc; \
    { \
    echo 'install: --no-document'; \
    echo 'update: --no-document'; \
    } >> /usr/local/etc/gemrc

ENV RUBY_MAJOR 2.7
ENV RUBY_VERSION 2.7.0
ENV RUBY_DOWNLOAD_SHA256 27d350a52a02b53034ca0794efe518667d558f152656c2baaf08f3d0c8b02343

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
# readline-dev vs libedit-dev: https://bugs.ruby-lang.org/issues/11869 and https://github.com/docker-library/ruby/issues/75
RUN set -eux; \
    \
    apk add --no-cache --virtual .ruby-builddeps \
    autoconf \
    bison \
    bzip2 \
    bzip2-dev \
    ca-certificates \
    coreutils \
    dpkg-dev dpkg \
    gcc \
    gdbm-dev \
    glib-dev \
    libc-dev \
    libffi-dev \
    libxml2-dev \
    libxslt-dev \
    linux-headers \
    make \
    ncurses-dev \
    openssl \
    openssl-dev \
    procps \
    readline-dev \
    ruby \
    tar \
    xz \
    yaml-dev \
    zlib-dev \
    ; \
    \
    wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz"; \
    echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum --check --strict; \
    \
    mkdir -p /usr/src/ruby; \
    tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1; \
    rm ruby.tar.xz; \
    \
    cd /usr/src/ruby; \
    \
    # https://github.com/docker-library/ruby/issues/196
    # https://bugs.ruby-lang.org/issues/14387#note-13 (patch source)
    # https://bugs.ruby-lang.org/issues/14387#note-16 ("Therefore ncopa's patch looks good for me in general." -- only breaks glibc which doesn't matter here)
    wget -O 'thread-stack-fix.patch' 'https://bugs.ruby-lang.org/attachments/download/7081/0001-thread_pthread.c-make-get_main_stack-portable-on-lin.patch'; \
    echo '3ab628a51d92fdf0d2b5835e93564857aea73e0c1de00313864a94a6255cb645 *thread-stack-fix.patch' | sha256sum --check --strict; \
    patch -p1 -i thread-stack-fix.patch; \
    rm thread-stack-fix.patch; \
    \
    # hack in "ENABLE_PATH_CHECK" disabling to suppress:
    #   warning: Insecure world writable dir
    { \
    echo '#define ENABLE_PATH_CHECK 0'; \
    echo; \
    cat file.c; \
    } > file.c.new; \
    mv file.c.new file.c; \
    \
    autoconf; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    # the configure script does not detect isnan/isinf as macros
    export ac_cv_func_isnan=yes ac_cv_func_isinf=yes; \
    ./configure \
    --build="$gnuArch" \
    --disable-install-doc \
    --enable-shared \
    ; \
    make -j "$(nproc)"; \
    make install; \
    \
    runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
    | tr ',' '\n' \
    | sort -u \
    | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-network --virtual .ruby-rundeps \
    $runDeps \
    bzip2 \
    ca-certificates \
    libffi-dev \
    procps \
    yaml-dev \
    zlib-dev \
    ; \
    apk del --no-network .ruby-builddeps; \
    \
    cd /; \
    rm -r /usr/src/ruby; \
    # verify we have no "ruby" packages installed
    ! apk --no-network list --installed \
    | grep -v '^[.]ruby-rundeps' \
    | grep -i ruby \
    ; \
    [ "$(command -v ruby)" = '/usr/local/bin/ruby' ]; \
    # rough smoke test
    ruby --version; \
    gem --version; \
    bundle --version

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH
# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"


############
## set up 
RUN apk add --no-cache logrotate
COPY ./assets/logrotate/logrotate.conf /etc/logrotate.d

COPY ./assets/httpd/httpd.conf /usr/local/apache2/conf/
COPY ./assets/httpd/server.key /usr/local/apache2/conf/
COPY ./assets/httpd/server.crt /usr/local/apache2/conf/
COPY ./assets/httpd/sslpassword.sh /usr/local/apache2/conf/
COPY ./assets/httpd/httpd-ssl.conf /usr/local/apache2/conf/extra/

COPY ./assets/cron/config /var/spool/cron/crontabs/root
COPY ./assets/cron/test.rb /bin/

COPY ./assets/entrypoint.sh /bin/

ENTRYPOINT ["/bin/entrypoint.sh"]