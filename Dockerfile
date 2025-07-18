FROM ghcr.io/zabdelillah/ffmpeg:gl-transitions
COPY "wrapper.sh" "/wrapper.sh"
RUN chmod +x /wrapper.sh; dnf install -y jq
ENTRYPOINT ["/wrapper.sh"]