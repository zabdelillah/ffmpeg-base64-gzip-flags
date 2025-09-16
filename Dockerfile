FROM ghcr.io/zabdelillah/ffmpeg:gl-transitions-gpu
COPY "wrapper.sh" "/wrapper.sh"
COPY "ffmpegwrapper.sh" "/ffmpegwrapper.sh"
COPY "hardcode.sh" "/hardcode.sh"
RUN chmod +x /*.sh; dnf install -y jq xorg-x11-server-Xvfb git; \
	git clone https://github.com/gl-transitions/gl-transitions.git; \
	bash /hardcode.sh; \
	mv gl-transitions/transitions/* ./; \
	apt install -y jq curl;
ENTRYPOINT ["/wrapper.sh"]

