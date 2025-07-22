FROM ghcr.io/zabdelillah/ffmpeg:gl-transitions
COPY "wrapper.sh" "/wrapper.sh"
COPY "ffmpegwrapper.sh" "/ffmpegwrapper.sh"
COPY "hardcode.sh" "/hardcode.sh"
RUN chmod +x /*.sh; dnf install -y jq xorg-x11-server-Xvfb git; \
	git clone https://github.com/gl-transitions/gl-transitions.git; \
	sh /hardcode.sh; \
	mv gl-transitions/transitions/* ./; \
ENTRYPOINT ["/wrapper.sh"]

