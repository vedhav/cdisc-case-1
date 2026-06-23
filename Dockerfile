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
#     by the generator and CORE digest). rocker/tidyverse already ships most. ---
RUN install2.r --error --skipinstalled jsonlite haven digest
COPY synthsdtm /app/synthsdtm
RUN R CMD INSTALL /app/synthsdtm

# --- CDISC CORE: cdisc-rules-engine pinned to a commit whose bundled
#     resources/cache includes the sdtmct-2026-03-27 package. Exposed as `core`. ---
ARG CORE_ENGINE_COMMIT=487da0ccd5adcbc8d50a7b5dce8564202de27e9b
RUN git clone https://github.com/cdisc-org/cdisc-rules-engine.git /app/cdisc-rules-engine \
 && git -C /app/cdisc-rules-engine checkout "${CORE_ENGINE_COMMIT}" \
 && pip3 install --no-cache-dir --break-system-packages -r /app/cdisc-rules-engine/requirements.txt
RUN printf '#!/bin/bash\ncd /app/cdisc-rules-engine && exec python3 core.py "$@"\n' > /usr/local/bin/core \
 && chmod +x /usr/local/bin/core

# --- Deterministic step scripts (fetch + generate) ---
COPY container/fetch.py /app/container/fetch.py
COPY container/generate.R /app/container/generate.R

WORKDIR /workspace
