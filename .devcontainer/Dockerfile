FROM ocaml/opam:debian-12-ocaml-5.4

COPY --chown=opam Makefile *.opam /tmp/yuka/
RUN cd /tmp/yuka \
 && sudo apt-get update \
 && make system-deps pin install OPAMSWITCH=$(opam switch show) \
 && sudo rm -rf /var/lib/apt/lists/* /tmp/yuka \
 && opam clean --download-cache --repo-cache
