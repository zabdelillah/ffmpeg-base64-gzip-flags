FROM ghcr.io/zabdelillah/ffmpeg:gl-transitions-gpu
COPY "wrapper.js" "/wrapper.js"
COPY "ffmpegwrapper.sh" "/ffmpegwrapper.sh"
COPY "hardcode.sh" "/hardcode.sh"
RUN chmod +x /*.sh; \
	git clone https://github.com/gl-transitions/gl-transitions.git; \
	bash /hardcode.sh; \
	mv gl-transitions/transitions/* ./; \
	apt install -y jq curl bc; \
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash; \
	bash -ic "nvm install v22.19.0"
ENTRYPOINT ["/root/.nvm/versions/node/v22.19.0/bin/node", "/wrapper.js"]

