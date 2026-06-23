# =============================================================================
# CDISC Case 1 agent image
#
# Extends mediforce-golden-image (R + tidyverse + Python + Claude Code) with:
#   - the synthsdtm R package (synthetic SDTM generator), installed locally
#   - CDISC CORE (cdisc-rules-engine) exposed as the `core` command, with its
#     bundled offline rules/CT cache (no CDISC_API_KEY needed)
#
# Skills are NOT baked in — they are read at run time from the repo via the
# workflow's externalSkillsRepo + skillsDir. Only the R package, the CORE
# engine, and the deterministic scripts need to be in the image.
#
# Build by hand (needs mediforce-golden-image):  docker build -t mediforce-agent:cdisc-case-1 .
# =============================================================================

FROM mediforce-golden-image

# --- synthsdtm + its R dependencies (haven for XPT export; jsonlite/digest used
#     by the generator and CORE digest). rocker/tidyverse already ships most.
#     NOTE: build commands are kept QUIET on purpose. The platform builds images
#     with execSync(..., {stdio:'pipe'}) and Node's default 1MB maxBuffer; a
#     chatty build (pip/git progress) overflows it and the build is killed. ---
RUN install2.r --error --skipinstalled jsonlite haven digest > /dev/null
COPY synthsdtm /app/synthsdtm
RUN R CMD INSTALL --no-docs --no-multiarch /app/synthsdtm > /dev/null

# --- CDISC CORE: cdisc-rules-engine. Shallow clone of a release tag (history-free)
#     so the image build completes on a cold builder; the tag ships the offline
#     resources/cache. Exposed as `core`. ---
ARG CORE_ENGINE_REF=v0.16.0
RUN git clone --depth 1 --branch "${CORE_ENGINE_REF}" --quiet https://github.com/cdisc-org/cdisc-rules-engine.git /app/cdisc-rules-engine \
 && pip3 install --quiet --no-input --no-cache-dir --break-system-packages -r /app/cdisc-rules-engine/requirements.txt
RUN printf '#!/bin/bash\ncd /app/cdisc-rules-engine && exec python3 core.py "$@"\n' > /usr/local/bin/core \
 && chmod +x /usr/local/bin/core

# --- Deterministic step scripts (fetch + generate) ---
COPY container/fetch.py /app/container/fetch.py
COPY container/generate.R /app/container/generate.R

WORKDIR /workspace
