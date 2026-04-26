#!/bin/bash
# Post-build hook for R2S profile
# Runs after firmware compilation

log_info "R2S post-build hook executed"
log_info "Firmware files:"
ls -lh "${OPENWRT_ROOT}/bin/targets/"*/*/
