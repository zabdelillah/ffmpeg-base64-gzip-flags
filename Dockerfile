FROM ghcr.io/zabdelillah/ffmpeg:gl-transitions
COPY "wrapper.sh" "/wrapper.sh"
COPY "ffmpegwrapper.sh" "/ffmpegwrapper.sh"
RUN chmod +x /*.sh; dnf install -y jq
ENTRYPOINT ["/wrapper.sh"]